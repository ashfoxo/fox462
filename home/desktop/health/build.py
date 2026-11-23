"""Builds the health page: Gadgetbridge (~/sync) + the Garmin backfill, one HTML file.

    build.py OUT PAGE CSS JS...     write the page to OUT, inlining CSS and JS
    build.py --bbox                 print "west,south,east,north" of every GPS point

Daily numbers come from the newest Gadgetbridge*.db export, with the Garmin
backfill (health-backfill) filling the days Gadgetbridge doesn't have.
Workouts are the recorded FIT/GPX files from both. Each file is parsed once
and cached by content in ~/.local/share/health/cache, because the FIT
library takes seconds per file.
"""
import base64
import hashlib
import io
import json
import math
import os
import sqlite3
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from datetime import date, datetime, timedelta
from pathlib import Path

import fitdecode

HOME = Path.home()
SYNC = HOME / "sync"
DATA = HOME / ".local/share/health"
GARMIN = DATA / "garmin"
CACHE = DATA / "cache"
VERSION = "4"          # bump when parse() output changes, to re-parse every file
MAX_POINTS = 2000       # per workout; plenty for a chart or a route line
SEMI = 180 / 2**31      # FIT semicircles -> degrees
COLS = ["t", "lat", "lon", "dist", "hr", "spd", "alt", "cad", "pwr", "vo", "gct", "sl"]
EFFORTS = {"1 km": 1000, "1 mi": 1609.344, "5 km": 5000, "10 km": 10000,
           "Half marathon": 21097.5, "Marathon": 42195}


def ms(dt):
    return int(dt.timestamp() * 1000)


def num(v, dp=None):
    if v is None or isinstance(v, (tuple, list)) or (isinstance(v, float) and math.isnan(v)):
        return None
    return round(v, dp) if dp is not None else v


def log(*a):
    print("health:", *a, file=sys.stderr)


# ---- Workout files --------------------------------------------------------

def read_fit(data):
    s, laps, recs, zones, vo2 = {}, [], [], None, None
    with fitdecode.FitReader(io.BytesIO(data)) as fr:
        for f in fr:
            if not isinstance(f, fitdecode.FitDataMessage):
                continue
            g = lambda k: f.get_value(k, fallback=None)
            if f.name == "session":
                s = {"start": g("start_time"), "sport": str(g("sport") or ""), "sub": str(g("sub_sport") or ""),
                     "secs": num(g("total_timer_time"), 0), "dist": num(g("total_distance"), 1),
                     "hr": g("avg_heart_rate"), "maxhr": g("max_heart_rate"), "cal": g("total_calories"),
                     "up": g("total_ascent"), "down": g("total_descent"),
                     "te": num(g("total_training_effect"), 1), "ate": num(g("total_anaerobic_training_effect"), 1),
                     "pwr": g("avg_power"), "np": g("normalized_power"),
                     "sl": num(g("avg_step_length"), 1), "vo": num(g("avg_vertical_oscillation"), 1),
                     "gct": num(g("avg_stance_time"), 1), "vr": num(g("avg_vertical_ratio"), 1)}
                cad = g("avg_running_cadence") or g("avg_cadence")
                s["cad"] = cad * 2 if cad and s["sport"] in ("running", "walking", "hiking") else cad
            elif f.name == "time_in_zone" and str(g("reference_mesg")) == "session":
                z = g("time_in_hr_zone")
                if z:
                    zones = [round(x or 0) for x in list(z)[:5]]   # zones 1-5; matches Garmin's hrTimeInZone_1..5
            elif f.global_mesg_num == 140 and g(7):   # undocumented Garmin message; field 7 is VO2 max * 65536 / 3.5, 0 if not estimated
                vo2 = round(g(7) * 3.5 / 65536, 1)
            elif f.name == "lap":
                laps.append({"time": g("total_timer_time"), "dist": g("total_distance"),
                             "hr": g("avg_heart_rate"), "maxhr": g("max_heart_rate"),
                             "spd": g("enhanced_avg_speed") or g("avg_speed"), "up": g("total_ascent"),
                             "cad": g("avg_running_cadence") or g("avg_cadence")})
            elif f.name == "record" and g("timestamp"):
                lat, lon = g("position_lat"), g("position_long")
                cad = g("cadence")
                if cad is not None:
                    cad = (cad + (g("fractional_cadence") or 0)) * 2   # one foot -> steps per minute
                recs.append({
                    "ts": g("timestamp"),
                    "lat": num(lat * SEMI, 6) if lat is not None else None,
                    "lon": num(lon * SEMI, 6) if lon is not None else None,
                    "dist": num(g("distance"), 1), "hr": g("heart_rate"),
                    "spd": num(g("enhanced_speed") if g("enhanced_speed") is not None else g("speed"), 3),
                    "alt": num(g("enhanced_altitude") if g("enhanced_altitude") is not None else g("altitude"), 1),
                    "cad": num(cad, 1), "pwr": g("power"),
                    "vo": num(g("vertical_oscillation"), 1), "gct": num(g("stance_time"), 1), "sl": num(g("step_length"), 1),
                })
    if not s and not recs:
        return None
    s["start"] = s.get("start") or recs[0]["ts"]
    s["zones"], s["vo2"] = zones, vo2
    return s, recs, laps


def read_gpx(data):
    root = ET.fromstring(data)
    ns = {"g": root.tag.split("}")[0].strip("{")}
    recs = []
    for p in root.iterfind(".//g:trkpt", ns):
        t = p.find("g:time", ns)
        if t is None:
            continue
        hr = next((e.text for e in p.iter() if e.tag.endswith("}hr")), None)
        ele = p.find("g:ele", ns)
        recs.append({
            "ts": datetime.fromisoformat(t.text.replace("Z", "+00:00")),
            "lat": num(float(p.get("lat")), 6), "lon": num(float(p.get("lon")), 6),
            "alt": num(float(ele.text), 1) if ele is not None else None,
            "hr": int(float(hr)) if hr else None,
        })
    if not recs:
        return None
    # GPX has no distance or speed: derive them from the positions.
    total = 0.0
    for a, b in zip([None] + recs, recs):
        if a:
            step = haversine(a["lat"], a["lon"], b["lat"], b["lon"])
            total += step
            dt = (b["ts"] - a["ts"]).total_seconds()
            b["spd"] = round(step / dt, 3) if dt > 0 else None
        b["dist"] = round(total, 1)
    hrs = [r["hr"] for r in recs if r["hr"]]
    s = {"start": recs[0]["ts"], "sport": "", "secs": round((recs[-1]["ts"] - recs[0]["ts"]).total_seconds()),
         "dist": round(total, 1), "hr": round(sum(hrs) / len(hrs)) if hrs else None, "maxhr": max(hrs, default=None),
         "zones": None}
    return s, recs, []


def haversine(la1, lo1, la2, lo2):
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = p2 - p1, math.radians(lo2 - lo1)
    return 2 * 6371000 * math.asin(math.sqrt(math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2))


def best_efforts(recs):
    """Fastest elapsed time over each EFFORTS distance, from the full-resolution recording."""
    pts = [(r["ts"].timestamp(), r["dist"]) for r in recs if r.get("dist") is not None]
    out = {}
    for name, d in EFFORTS.items():
        if len(pts) < 2 or pts[-1][1] - pts[0][1] < d:
            continue
        best, j = None, 0
        for i in range(len(pts)):
            while j < len(pts) and pts[j][1] - pts[i][1] < d:
                j += 1
            if j == len(pts):
                break
            t = pts[j][0] - pts[i][0]
            if t > 0 and d / t < 7 and (best is None or t < best):   # over 7 m/s is a GPS jump, not you
                best = t
        if best:
            out[name] = round(best)
    return out


def _check_efforts():
    from datetime import timedelta, timezone
    t0 = datetime(2026, 1, 1, tzinfo=timezone.utc)
    recs = [{"ts": t0 + timedelta(seconds=i), "dist": 4.0 * i} for i in range(1300)]   # 4 m/s for 5.2 km
    assert best_efforts(recs) == {"1 km": 250, "1 mi": 403, "5 km": 1250}, best_efforts(recs)


_check_efforts()


def parse(kind, data):
    got = read_fit(data) if kind == "fit" else read_gpx(data)
    if not got:
        return None
    s, recs, laps = got
    t0 = s.pop("start")
    gps = [(r["lon"], r["lat"]) for r in recs if r.get("lat") is not None]
    step = max(1, math.ceil(len(recs) / MAX_POINTS))
    return {
        **{k: v for k, v in s.items() if v not in (None, "")},
        "start": ms(t0), "src": kind,
        "best": best_efforts(recs),
        "bbox": [min(p[0] for p in gps), min(p[1] for p in gps), max(p[0] for p in gps), max(p[1] for p in gps)] if gps else None,
        "track": {"cols": COLS, "rows": [[round((r["ts"] - t0).total_seconds())] + [r.get(c) for c in COLS[1:]]
                                          for r in recs[::step]]} if len(recs) > 20 else None,
        "laps": laps if len(laps) > 1 else [],
    }


def recordings():
    """(kind, bytes) for every workout file: Gadgetbridge's ZIP and auto exports, and the Garmin backfill."""
    for z in sorted(SYNC.rglob("gadgetbridge_*.zip")):
        if ".stversions" in z.parts:
            continue
        with zipfile.ZipFile(z) as zf:
            for name in zf.namelist():
                if "/ACTIVITY/" in name and name.lower().endswith(".fit"):
                    yield "fit", zf.read(name)
    for root in (SYNC, GARMIN / "fit"):
        for p in sorted(root.rglob("*")):
            if ".stversions" in p.parts:   # Syncthing's old versions
                continue
            ext = p.suffix.lower()
            if ext in (".fit", ".gpx"):
                yield ext[1:], p.read_bytes()


def cached_parse(kind, data):
    key = hashlib.sha256(VERSION.encode() + data).hexdigest()
    f = CACHE / f"{key}.json"
    if f.exists():
        return json.loads(f.read_text())
    try:
        w = parse(kind, data)
    except Exception as e:  # one broken file must not hide the rest; cached as null so it isn't retried
        log(f"skipped a {kind} file: {e}")
        w = None
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".part")
    tmp.write_text(json.dumps(w, separators=(",", ":"), default=str))
    tmp.replace(f)
    return w


def workouts(gb_names):
    out = []
    for kind, data in recordings():
        w = cached_parse(kind, data)
        if not w:
            continue
        # The same workout again (ZIP and auto export, GPX and FIT, phone and Garmin): keep the FIT, or the first.
        dup = next((o for o in out if abs(o["start"] - w["start"]) < 120_000), None)
        if dup is not None:
            if dup["src"] == "fit" or kind == "gpx":
                continue
            out.remove(dup)
        out.append(w)

    garmin = load(GARMIN / "activities.json") or []
    for w in out:
        g = next((a for a in garmin if abs(a.get("beginTimestamp", 0) - w["start"]) < 120_000), None)
        if g:
            w["name"], w["place"] = g.get("activityName"), g.get("locationName")
            w["type"] = (g.get("activityType") or {}).get("typeKey")
            # Garmin's own numbers fill what the file lacks (the API strips some FIT fields).
            for k, gk in [("secs", "duration"), ("dist", "distance"), ("hr", "averageHR"), ("maxhr", "maxHR"),
                          ("cal", "calories"), ("up", "elevationGain"), ("down", "elevationLoss"),
                          ("te", "aerobicTrainingEffect"), ("ate", "anaerobicTrainingEffect"), ("load", "activityTrainingLoad")]:
                if w.get(k) is None and g.get(gk) is not None:
                    w[k] = round(g[gk], 1)
            if g.get("hrTimeInZone_1") is not None:   # Garmin's split wins over the file's
                w["zones"] = [round(g.get(f"hrTimeInZone_{i}") or 0) for i in range(1, 6)]
        else:
            w["name"] = next((n for s, e, n in gb_names if s - 120_000 <= w["start"] <= e), None)
    # shortcut: a Gadgetbridge workout with no FIT/GPX file isn't listed; turn on its auto FIT export instead.
    return sorted(out, key=lambda w: w["start"])


# ---- Daily numbers --------------------------------------------------------

def load(p):
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return None


def gadgetbridge():
    """{day: {field: value}} from the newest export, the device name, and workout names."""
    dbs = [p for p in SYNC.rglob("Gadgetbridge*.db") if ".stversions" not in p.parts]
    if not dbs:
        log("no Gadgetbridge*.db in ~/sync; Garmin backfill only")
        return {}, None, "watch", []
    db = max(dbs, key=lambda p: p.stat().st_mtime)
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)

    def q(sql):
        try:
            return con.execute(sql).fetchall()
        except sqlite3.Error:   # a table this watch doesn't have
            return []

    day = "date(TIMESTAMP/1000,'unixepoch','localtime')"
    days = {}
    put = lambda d, **kv: days.setdefault(d, {}).update({k: v for k, v in kv.items() if v is not None})
    # Steps: the Garmin STEPS column is a running count through the day, so a day's steps is its highest value.
    for d, v in q("select date(TIMESTAMP,'unixepoch','localtime') d, max(STEPS) from GARMIN_ACTIVITY_SAMPLE group by d"):
        put(d, steps=v or None)
    for d, v in q(f"select {day} d, max(SLEEP_SCORE) from GARMIN_SLEEP_STATS_SAMPLE group by d"):
        put(d, score=v)
    for d, v in q(f"select {day} d, min(HEART_RATE) from GARMIN_HEART_RATE_RESTING_SAMPLE where HEART_RATE > 0 group by d"):
        put(d, rhr=v)
    for d, v, lo, hi in q(f"select {day} d, max(LAST_NIGHT_AVERAGE), max(BASELINE_BALANCED_LOWER), max(BASELINE_BALANCED_UPPER) from GARMIN_HRV_SUMMARY_SAMPLE group by d"):
        put(d, hrv=v, hrvLo=lo, hrvHi=hi)
    for d, lo, hi in q(f"select {day} d, min(ENERGY), max(ENERGY) from GARMIN_BODY_ENERGY_SAMPLE where ENERGY between 0 and 100 group by d"):
        put(d, bbLo=lo, bbHi=hi)
    for d, v in q(f"select {day} d, round(avg(STRESS)) from GARMIN_STRESS_SAMPLE where STRESS between 0 and 100 group by d"):
        put(d, stress=v)
    for d, v in q(f"select {day} d, round(avg(RESPIRATORY_RATE),1) from GARMIN_RESPIRATORY_RATE_SAMPLE where RESPIRATORY_RATE > 0 group by d"):
        put(d, resp=v)
    for d, v in q(f"select {day} d, sum(MODERATE) + 2*sum(VIGOROUS) from GARMIN_INTENSITY_MINUTES_SAMPLE group by d"):
        put(d, intensity=v)

    # Sleep stages: each sample marks a stage start that lasts until the next one (a gap
    # over 3 h starts a new night). Codes 1 awake, 2 light, 3 deep, 4 REM. Filed under the day you woke.
    stages = q("select TIMESTAMP, STAGE from GARMIN_SLEEP_STAGE_SAMPLE order by TIMESTAMP")
    # A night still going when the phone exported (the midnight export) is left out, not shown half-slept.
    if stages and db.stat().st_mtime * 1000 - stages[-1][0] < 3 * 3600e3:
        while len(stages) > 1 and stages[-1][0] - stages[-2][0] <= 3 * 3600e3:
            stages.pop()
        stages.pop()
    mins = None
    for i, (t, s) in enumerate(stages):
        nxt = stages[i + 1] if i + 1 < len(stages) else None
        if nxt and nxt[0] - t <= 3 * 3600e3:
            mins = mins or {1: 0, 2: 0, 3: 0, 4: 0}
            mins[s] = mins.get(s, 0) + (nxt[0] - t) / 60000
        elif mins:
            d = datetime.fromtimestamp(t / 1000).date().isoformat()
            put(d, deep=round(mins[3] / 60, 2), light=round(mins[2] / 60, 2), rem=round(mins[4] / 60, 2), awake=round(mins[1] / 60, 2))
            mins = None

    dev = q("select MANUFACTURER || ' ' || MODEL from DEVICE limit 1")
    names = q("select START_TIME, END_TIME, NAME from BASE_ACTIVITY_SUMMARY")
    exported = datetime.fromtimestamp(db.stat().st_mtime).strftime("%b %-d, %H:%M")
    return days, exported, dev[0][0] if dev else "watch", names


def garmin_days():
    days = {}
    put = lambda d, **kv: days.setdefault(d, {}).update({k: v for k, v in kv.items() if v is not None})
    pos = lambda v: v if isinstance(v, (int, float)) and v > 0 else None
    for f in sorted((GARMIN / "daily-summaries").glob("*.json")):
        for r in (load(f) or {}).get("data") or []:
            mv, hr, bb = r.get("movement") or {}, r.get("heartRate") or {}, r.get("bodyBattery") or {}
            im = r.get("intensityMinutes") or {}
            put(r["calendarDate"], steps=pos((mv.get("steps") or {}).get("value")), rhr=pos(hr.get("restingValue")),
                bbLo=bb.get("minValue"), bbHi=pos(bb.get("maxValue")),
                stress=pos((r.get("stress") or {}).get("avgLevel")), resp=pos((r.get("respiration") or {}).get("avgValue")),
                intensity=(im.get("moderate") or 0) + 2 * (im.get("vigorous") or 0) if im else None)
    for f in sorted((GARMIN / "sleep-summaries").glob("*.json")):
        for r in load(f) or []:
            h = lambda k: round(r[k] / 3600, 2) if r.get(k) is not None else None
            if not r.get("sleepTimeSeconds"):
                continue
            put(r["calendarDate"], deep=h("deepSleepSeconds"), light=h("lightSleepSeconds"), rem=h("remSleepSeconds"),
                awake=h("awakeSleepSeconds"), score=((r.get("sleepScores") or {}).get("overall") or {}).get("value"))
    for f in sorted((GARMIN / "hrv-summaries").glob("*.json")):
        for r in (load(f) or {}).get("hrvSummaries") or []:
            b = r.get("baseline") or {}
            put(r["calendarDate"], hrv=r.get("lastNightAvg"), hrvLo=b.get("balancedLow"), hrvHi=b.get("balancedUpper"))
    return days


# ---- Training load (formulas and sources: see the README) -----------------

def trimp(w, rest, top):
    """Banister TRIMP: minutes weighted by heart-rate reserve, so hard minutes count for more."""
    hr = COLS.index("hr")
    rows = [(r[0], r[hr]) for r in (w.get("track") or {}).get("rows", []) if r[hr]]
    if len(rows) > 1:
        parts = [(min(b[0] - a[0], 60), a[1]) for a, b in zip(rows, rows[1:])]   # a gap over a minute is a pause
    elif w.get("hr") and w.get("secs"):
        parts = [(w["secs"], w["hr"])]
    else:
        return 0
    total = 0
    for secs, bpm in parts:
        x = min(max((bpm - rest) / (top - rest), 0), 1)
        # shortcut: 1.92 is Banister's men's weighting (women's is 1.67); change it if it fits you better.
        total += secs / 60 * x * 0.64 * math.exp(1.92 * x)
    return total


assert 50 < trimp({"hr": 125, "secs": 3600}, 50, 200) < 50.3   # an hour at half your reserve
assert trimp({"track": {"rows": [[0] + [None] * 3 + [125], [60] + [None] * 3 + [125]]}}, 50, 200) == \
    trimp({"hr": 125, "secs": 60}, 50, 200)


def training(days, ws):
    """Each day's fitness (42-day) and fatigue (7-day) load, and efficiency on easy runs, into days."""
    top = max((w.get("maxhr") or 0 for w in ws), default=0)   # your highest recorded heart rate
    rhrs = sorted((d, v["rhr"]) for d, v in days.items() if v.get("rhr"))
    load, ef = {}, {}
    for w in ws:
        d = datetime.fromtimestamp(w["start"] / 1000).date()
        rest = next((v for k, v in reversed(rhrs) if k <= d.isoformat()), 60)   # latest resting HR on or before the day
        if top <= rest:
            continue
        load[d] = load.get(d, 0) + trimp(w, rest, top)
        easy = w.get("hr") and (w["hr"] - rest) / (top - rest) < 0.75
        if easy and "running" in f"{w.get('sport')} {w.get('type')}" and w.get("dist") and w.get("secs"):
            ef[d.isoformat()] = round(w["dist"] / w["secs"] * 60 / w["hr"], 2)   # metres a minute per bpm
    if not load:
        return
    fit = fat = 0
    d = min(load)
    while d <= date.today():   # rest days count too: both averages decay through them
        fit += (load.get(d, 0) - fit) / 42
        fat += (load.get(d, 0) - fat) / 7
        days.setdefault(d.isoformat(), {}).update(fit=round(fit), fat=round(fat))
        d += timedelta(days=1)
    for k, v in ef.items():
        days[k]["ef"] = v


# ---- Map and page ---------------------------------------------------------

def bbox_of(ws):
    """Area of the workouts near your newest one (about 100 km): the map follows where you are now."""
    boxes = [w["bbox"] for w in ws if w.get("bbox")]
    if not boxes:
        return None
    mid = lambda b: ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
    cx, cy = mid(boxes[-1])
    boxes = [b for b in boxes if abs(mid(b)[0] - cx) < 1 and abs(mid(b)[1] - cy) < 1]
    return [min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)]


def map_tiles(box, tmp):
    """The workouts' area cut from the region file (health-map), base64; '' if there's no map."""
    region = DATA / "region.pmtiles"
    if not box:
        return ""
    if not region.exists():
        log("no map yet. Run health-map once to add one.")
        return ""
    rw, rs, re_, rn = map(float, (DATA / "region.bbox").read_text().split(","))
    w, s, e, n = box
    if w < rw or s < rs or e > re_ or n > rn:
        log("some workouts are outside your downloaded map. Run: health-map")
    pad = 0.01
    out = Path(tmp) / "tiles.pmtiles"
    sub = f"{w - pad},{s - pad},{e + pad},{n + pad}"
    r = subprocess.run(["pmtiles", "extract", str(region), str(out), f"--bbox={sub}", "--maxzoom=15"],
                       capture_output=True)
    return base64.b64encode(out.read_bytes()).decode() if r.returncode == 0 and out.exists() else ""


def main():
    if "--bbox" in sys.argv:
        box = bbox_of(workouts([]))
        if not box:
            sys.exit("health: no workouts with GPS yet")
        print(",".join(f"{v:f}" for v in box))
        return
    out, page, css, *js = sys.argv[1:]

    gb, exported, device, names = gadgetbridge()
    days = garmin_days()
    for d, v in gb.items():   # Gadgetbridge wins wherever it has the number
        days.setdefault(d, {}).update(v)
    ws = workouts(names)
    for w in ws:   # VO2 max goes on its workout's day (newest wins), so the page reads it like any daily number
        if w.get("vo2"):
            days.setdefault(datetime.fromtimestamp(w["start"] / 1000).date().isoformat(), {})["vo2"] = w["vo2"]
    training(days, ws)
    data ={"device": device, "exported": exported, "days": [{"d": d, **v} for d, v in sorted(days.items())],
            "workouts": [{k: v for k, v in w.items() if k != "bbox" or v} for w in ws]}

    with tempfile.TemporaryDirectory() as tmp:
        tiles = map_tiles(bbox_of(ws), tmp)
    html = Path(page).read_text()
    libs = "<style>\n" + Path(css).read_text() + "</style>\n<script>\n" + "".join(Path(j).read_text() for j in js) + "</script>\n"
    # </ escaped so a workout name can't close the script tag.
    blob = json.dumps(data, separators=(",", ":"), default=str).replace("</", "<\\/")
    payload = (f'<script type="application/json" id="data">{blob}</script>\n'
               f'<script type="text/plain" id="maptiles">{tiles}</script>\n')
    head, rest = html.split("<!--LIBS-->", 1)
    mid, tail = rest.split("<!--DATA-->", 1)
    old = os.umask(0o077)
    try:
        Path(out).write_text(head + libs + mid + payload + tail)
    finally:
        os.umask(old)


if __name__ == "__main__":
    main()
