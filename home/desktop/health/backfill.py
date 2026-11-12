"""One-off copy of your Garmin Connect history, via Garmin's Personal API.

    backfill.py OUT_DIR [--since YYYY-MM-DD]     API key on stdin

Writes into OUT_DIR:
    activities.json             every activity summary
    fit/<id>.fit                each activity's original file (.gpx/.tcx if that's what it was)
    <endpoint>/<start>.json     daily stats in 28-day chunks (steps, stress, sleep, ...)
    sleep/<date>.json, hrv/<date>.json   per-night detail (sleep stages, HRV readings)

Resumable: whatever is already on disk is skipped, so a run that was
throttled or interrupted just picks up where it stopped. Garmin doesn't
publish rate limits, so it goes one request a second and backs off on 429.
"""
import io
import json
import sys
import time
import urllib.error
import urllib.request
import zipfile
from datetime import date, timedelta
from pathlib import Path

BASE = "https://personal.connectapi.garmin.com"
TOKEN_PATH = "/personalapitoken-service/personal-api/personal-api-key/token"
CHUNK = 28  # days; the smallest per-request window any range endpoint allows

# Date-range endpoints: name -> path template.
RANGES = {
    "steps": "/usersummary-service/stats/steps/daily/{s}/{e}",
    "stress": "/usersummary-service/stats/stress/daily/{s}/{e}",
    "sleep-summaries": "/sleep-service/sleep/dailySleepSummariesByDate?startDate={s}&endDate={e}",
    "body-battery": "/wellness-service/wellness/bodyBattery/reports/daily?startDate={s}&endDate={e}",
    "daily-summaries": "/usersummary-service/v2/dailysummaries?startDate={s}&endDate={e}",
    "hrv-summaries": "/hrv-service/hrv/daily/{s}/{e}",
}
# One-day endpoints: the detail the range ones don't carry.
DAYS = {
    "sleep": "/sleep-service/sleep/dailySleep?date={d}",
    "hrv": "/hrv-service/hrv/{d}",
}


def chunks(start, end, n):
    """Inclusive [start, end] as consecutive windows of at most n days."""
    while start <= end:
        stop = min(start + timedelta(days=n - 1), end)
        yield start, stop
        start = stop + timedelta(days=1)


assert list(chunks(date(2026, 1, 1), date(2026, 1, 30), 28)) == [
    (date(2026, 1, 1), date(2026, 1, 28)), (date(2026, 1, 29), date(2026, 1, 30))]
assert list(chunks(date(2026, 1, 2), date(2026, 1, 1), 28)) == []


class Api:
    def __init__(self, key):
        self.key = key
        self.token = None

    def _token(self):
        req = urllib.request.Request(BASE + TOKEN_PATH, method="POST",
                                     headers={"Authorization": f"ApiKey {self.key}", "Accept": "*/*"})
        with urllib.request.urlopen(req, timeout=30) as r:
            self.token = r.read().decode().strip()

    def get(self, path, accept="application/json"):
        """Body bytes, or None for 404 (no data that day). Retries 429/5xx; re-tokens once on 401."""
        if self.token is None:
            self._token()
        retried_auth = False
        for attempt in range(8):
            time.sleep(1)
            req = urllib.request.Request(BASE + path, headers={
                "Authorization": f"Bearer {self.token}", "Accept": accept})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return r.read()
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    return None
                if e.code == 401 and not retried_auth:  # tokens last 24 h
                    retried_auth = True
                    self._token()
                    continue
                if e.code == 429 or e.code >= 500:
                    wait = int(e.headers.get("Retry-After") or 0) or min(30 * 2 ** attempt, 900)
                    print(f"  HTTP {e.code}, waiting {wait}s", file=sys.stderr)
                    time.sleep(wait)
                    continue
                raise SystemExit(f"backfill: GET {path} -> HTTP {e.code}: {e.read()[:300]!r}")
            except urllib.error.URLError as e:
                print(f"  network error ({e.reason}), retrying", file=sys.stderr)
                time.sleep(30)
        raise SystemExit(f"backfill: gave up on {path}; run again later to resume")


def save(path, data):
    """Write atomically, so an interrupted run never leaves a half file to be skipped."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)


def activities(api, out):
    acts, start = [], 0
    while True:
        page = json.loads(api.get(f"/activitylist-service/activities/search/activities?start={start}&limit=100") or b"[]")
        if not page:
            break
        acts += page
        start += len(page)
        print(f"  {len(acts)} activities listed", file=sys.stderr)
    save(out / "activities.json", json.dumps(acts).encode())

    for i, a in enumerate(acts, 1):
        aid = int(a["activityId"])  # an int, so it can't smuggle a path
        if list((out / "fit").glob(f"{aid}.*")):
            continue
        print(f"  file {i}/{len(acts)}: {a.get('activityName') or aid}", file=sys.stderr)
        data = api.get(f"/download-service/files/activity/{aid}",
                       accept="application/zip, application/x-zip-compressed, application/octet-stream")
        if not data:
            continue
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            # Only the first recognised file, renamed to the ID: names inside the ZIP are never used as paths.
            for name in z.namelist():
                ext = Path(name).suffix.lower()
                if ext in (".fit", ".gpx", ".tcx"):
                    save(out / "fit" / f"{aid}{ext}", z.read(name))
                    break
    return acts


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    out = Path(sys.argv[1])
    key = sys.stdin.readline().strip()
    if not key:
        raise SystemExit("backfill: no API key on stdin")
    api = Api(key)
    today = date.today()

    print("Activities…", file=sys.stderr)
    acts = activities(api, out)

    if "--since" in sys.argv:
        since = date.fromisoformat(sys.argv[sys.argv.index("--since") + 1])
    elif acts:
        since = min(date.fromisoformat(a["startTimeLocal"][:10]) for a in acts)
    else:
        raise SystemExit("backfill: no activities to date from; pass --since YYYY-MM-DD")
    print(f"Daily data from {since}…", file=sys.stderr)

    for name, tmpl in RANGES.items():
        for s, e in chunks(since, today, CHUNK):
            f = out / name / f"{s}.json"
            if f.exists() and e < today:  # the chunk holding today is still filling in
                continue
            save(f, api.get(tmpl.format(s=s, e=e)) or b"null")
        print(f"  {name} done", file=sys.stderr)

    for name, tmpl in DAYS.items():
        d = since
        while d <= today:
            f = out / name / f"{d}.json"
            if not f.exists() or d >= today - timedelta(days=1):
                save(f, api.get(tmpl.format(d=d)) or b"null")
            d += timedelta(days=1)
        print(f"  {name} done", file=sys.stderr)

    print(f"Done: {len(acts)} activities, daily data {since} → {today}, in {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
