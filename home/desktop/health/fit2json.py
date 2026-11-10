"""Gadgetbridge activity files -> compact JSON for the health page.

    fit2json.py SYNC_DIR            JSON on stdout: {"<start ms>": activity}
    fit2json.py SYNC_DIR --bbox     "west,south,east,north" of every GPS point

Reads ACTIVITY/*.fit inside every gadgetbridge_*.zip export and any *.fit or
*.gpx below SYNC_DIR (Gadgetbridge's auto FIT and GPX exports). One activity
per start time: FIT wins over GPX, and a duplicate start is skipped.
"""
import io
import json
import math
import sys
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import fitdecode

MAX_POINTS = 2000          # per activity; plenty for a chart or a route line
SEMI = 180 / 2**31         # FIT semicircles -> degrees
COLS = ["t", "lat", "lon", "dist", "hr", "spd", "alt", "cad", "pwr", "vo", "gct", "sl"]


def ms(dt):
    return int(dt.timestamp() * 1000)


def num(v, dp=None):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    return round(v, dp) if dp is not None else v


def read_fit(data):
    session, laps, recs = {}, [], []
    with fitdecode.FitReader(io.BytesIO(data)) as fr:
        for f in fr:
            if not isinstance(f, fitdecode.FitDataMessage):
                continue
            g = lambda k: f.get_value(k, fallback=None)
            if f.name == "session":
                session = {"start": g("start_time"), "sport": g("sport")}
            elif f.name == "lap":
                laps.append({
                    "start": g("start_time"), "time": g("total_timer_time"), "dist": g("total_distance"),
                    "hr": g("avg_heart_rate"), "maxhr": g("max_heart_rate"),
                    "spd": g("enhanced_avg_speed") or g("avg_speed"), "up": g("total_ascent"), "down": g("total_descent"),
                    "cad": g("avg_running_cadence") or g("avg_cadence"),
                })
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
    if not recs:
        return None
    start = session.get("start") or recs[0]["ts"]
    return start, str(session.get("sport") or ""), recs, laps


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
        if a and a["lat"] is not None and b["lat"] is not None:
            total += haversine(a["lat"], a["lon"], b["lat"], b["lon"])
            dt = (b["ts"] - a["ts"]).total_seconds()
            b["spd"] = round(haversine(a["lat"], a["lon"], b["lat"], b["lon"]) / dt, 3) if dt > 0 else None
        b["dist"] = round(total, 1)
    return recs[0]["ts"], "", recs, []


def haversine(la1, lo1, la2, lo2):
    r = 6371000
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = p2 - p1, math.radians(lo2 - lo1)
    return 2 * r * math.asin(math.sqrt(math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2))


def sources(root):
    for z in sorted(root.rglob("gadgetbridge_*.zip")):
        if ".stversions" in z.parts:
            continue
        with zipfile.ZipFile(z) as zf:
            for name in zf.namelist():
                if "/ACTIVITY/" in name and name.lower().endswith(".fit"):
                    yield "fit", zf.read(name)
    for p in sorted(root.rglob("*")):
        if ".stversions" in p.parts:   # Syncthing's old versions
            continue
        if p.suffix.lower() == ".fit":
            yield "fit", p.read_bytes()
        elif p.suffix.lower() == ".gpx":
            yield "gpx", p.read_bytes()


def main():
    root = Path(sys.argv[1])
    acts = {}
    for kind, data in sources(root):
        try:
            got = read_fit(data) if kind == "fit" else read_gpx(data)
        except Exception as e:  # one broken file must not hide the rest
            print(f"fit2json: skipped a {kind} file: {e}", file=sys.stderr)
            continue
        if not got:
            continue
        start, sport, recs, laps = got
        key = ms(start)
        # Same activity again (zip and auto export): keep the FIT, or the first.
        dup = next((k for k in acts if abs(k - key) < 120_000), None)
        if dup is not None and (acts[dup]["src"] == "fit" or kind == "gpx"):
            continue
        if dup is not None:
            del acts[dup]
        acts[key] = {"src": kind, "sport": sport, "start": start, "recs": recs, "laps": laps}

    if "--bbox" in sys.argv:
        pts = [(r["lon"], r["lat"]) for a in acts.values() for r in a["recs"] if r.get("lat") is not None]
        if not pts:
            sys.exit("fit2json: no GPS points")
        lons, lats = zip(*pts)
        print(f"{min(lons)},{min(lats)},{max(lons)},{max(lats)}")
        return

    out = {}
    for key, a in acts.items():
        recs, t0 = a["recs"], a["start"]
        step = max(1, math.ceil(len(recs) / MAX_POINTS))
        rows = [[round((r["ts"] - t0).total_seconds())] + [r.get(c) for c in COLS[1:]] for r in recs[::step]]
        laps = [{**l, "start": ms(l["start"]) if l["start"] else None} for l in a["laps"]]
        out[str(key)] = {"src": a["src"], "sport": a["sport"], "cols": COLS, "rows": rows, "laps": laps}
    json.dump(out, sys.stdout, separators=(",", ":"), default=str)


if __name__ == "__main__":
    main()
