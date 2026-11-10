# `health`: your Gadgetbridge data as charts, with no server. It reads the
# newest database the phone exports anywhere under ~/sync (Gadgetbridge →
# Settings → Automations → auto export), plus the activity FIT/GPX files (auto
# FIT/GPX export, and those inside its ZIP exports), writes one page into
# $XDG_RUNTIME_DIR (RAM) and opens it in the clean Firefox; the sandboxed
# browsers can't see local files. The page makes no network requests: the map
# libraries are inlined, and the map tiles come from the local region file.
#
# `health-map`: downloads the OpenStreetMap area around your activities (from
# Protomaps' daily build) into ~/.local/share/health. The one step that goes
# online; the server sees the area you ask for, via Mullvad. Run it once, and
# again when you've been active somewhere new (`health` tells you).
{ pkgs, ... }:
let
  c = (import ../../../lib/palette.nix).for "quickshell";
  page = pkgs.replaceVars ./page.html {
    inherit (c) bg surf line fg dim faint;
    accent = c.forest_text;
  };

  # Pinned map libraries, inlined into the page.
  lib = { url, hash }: pkgs.fetchurl { inherit url hash; };
  maplibreJs = lib { url = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"; hash = "sha256-vpYzxNhw4m+zfxz+XFp3GBZnEUAD6hYgeseFDY2ordE="; };
  maplibreCss = lib { url = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css"; hash = "sha256-V2sIX92Uh6ZaGSFTKMHghsB85b9toJtmazgG09AI2uk="; };
  pmtilesJs = lib { url = "https://unpkg.com/pmtiles@3.2.1/dist/pmtiles.js"; hash = "sha256-NnwZ+JNtHWwbGCCw3uBT95P8KSd2VcPkcfXtTTe18EU="; };
  basemapsJs = lib { url = "https://unpkg.com/@protomaps/basemaps@5.1.0/dist/basemaps.js"; hash = "sha256-OX3U/ZCryYv6vN8tB0Q2I2G1SIRNabrn955/5vG7NcE="; };

  python = pkgs.python3.withPackages (p: [ p.fitdecode ]);
  fit2json = "${python}/bin/python3 -I ${./fit2json.py}";
  mapDir = "$HOME/.local/share/health";

  health = pkgs.writeShellApplication {
    name = "health";
    runtimeInputs = with pkgs; [ sqlite jq coreutils gnused findutils gawk pmtiles ];
    text = ''
      # The newest export, anywhere under ~/sync (not Syncthing's old versions).
      db=$(find "$HOME/sync" -maxdepth 4 -name 'Gadgetbridge*.db' -not -path '*/.stversions/*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
      [ -n "$db" ] || { echo "health: no Gadgetbridge*.db in ~/sync" >&2; exit 1; }

      # One JSON array per query; [] when a table is empty or missing.
      # Steps: the Garmin STEPS column is a running count through the day, so a
      # day's steps is its highest value, not the sum.
      q() { sqlite3 -readonly -json "$db" "$1" 2>/dev/null | grep . || echo '[]'; }
      day="date(TIMESTAMP/1000,'unixepoch','localtime')"

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      ${fit2json} "$HOME/sync" > "$work/tracks.json" || echo '{}' > "$work/tracks.json"

      jq -cn \
        --arg device "$(sqlite3 -readonly "$db" "select MANUFACTURER || ' ' || MODEL from DEVICE limit 1" 2>/dev/null || echo watch)" \
        --arg exported "$(date -r "$db" '+%b %-d, %H:%M')" \
        --argjson steps "$(q "select date(TIMESTAMP,'unixepoch','localtime') d, max(STEPS) v from GARMIN_ACTIVITY_SAMPLE group by d order by d")" \
        --argjson sleepScore "$(q "select $day d, max(SLEEP_SCORE) v from GARMIN_SLEEP_STATS_SAMPLE group by d order by d")" \
        --argjson rhr "$(q "select $day d, min(HEART_RATE) v from GARMIN_HEART_RATE_RESTING_SAMPLE where HEART_RATE > 0 group by d order by d")" \
        --argjson hrv "$(q "select $day d, max(LAST_NIGHT_AVERAGE) v, max(BASELINE_BALANCED_LOWER) lo, max(BASELINE_BALANCED_UPPER) hi from GARMIN_HRV_SUMMARY_SAMPLE group by d order by d")" \
        --argjson energy "$(q "select $day d, min(ENERGY) lo, max(ENERGY) hi from GARMIN_BODY_ENERGY_SAMPLE where ENERGY between 0 and 100 group by d order by d")" \
        --argjson stress "$(q "select $day d, round(avg(STRESS)) v from GARMIN_STRESS_SAMPLE where STRESS between 0 and 100 group by d order by d")" \
        --argjson resp "$(q "select $day d, round(avg(RESPIRATORY_RATE),1) v from GARMIN_RESPIRATORY_RATE_SAMPLE where RESPIRATORY_RATE > 0 group by d order by d")" \
        --argjson intensity "$(q "select $day d, sum(MODERATE) + 2*sum(VIGOROUS) v from GARMIN_INTENSITY_MINUTES_SAMPLE group by d order by d")" \
        --argjson stages "$(q "select TIMESTAMP t, STAGE s from GARMIN_SLEEP_STAGE_SAMPLE order by t")" \
        --argjson workouts "$(q "select _id id, NAME name, START_TIME start, END_TIME end, SUMMARY_DATA summary from BASE_ACTIVITY_SUMMARY order by START_TIME")" \
        --argjson workoutHr "$(q "select w._id id, s.TIMESTAMP t, s.HEART_RATE hr from BASE_ACTIVITY_SUMMARY w join GARMIN_ACTIVITY_SAMPLE s on s.TIMESTAMP between w.START_TIME/1000 and w.END_TIME/1000 where s.HEART_RATE between 30 and 220 order by w._id, s.TIMESTAMP")" \
        --slurpfile tracks "$work/tracks.json" \
        '$ARGS.named + {tracks: $tracks[0]}' > "$work/data.json"

      # Map tiles: just the area of your activities, cut from the region file.
      : > "$work/tiles.b64"
      region="${mapDir}/region.pmtiles"
      if bbox=$(${fit2json} "$HOME/sync" --bbox 2>/dev/null); then
        if [ -f "$region" ]; then
          IFS=, read -r w s e n <<< "$bbox"
          IFS=, read -r rw rs re rn < "${mapDir}/region.bbox"
          if awk -v w="$w" -v s="$s" -v e="$e" -v n="$n" -v rw="$rw" -v rs="$rs" -v re="$re" -v rn="$rn" \
               'BEGIN { exit !(w < rw || s < rs || e > re || n > rn) }'; then
            echo "health: some activities are outside your downloaded map. Run: health-map" >&2
          fi
          # A little margin around the routes, street-level detail at most.
          pad=0.01
          sub=$(awk -v w="$w" -v s="$s" -v e="$e" -v n="$n" -v p="$pad" 'BEGIN { printf "%f,%f,%f,%f", w-p, s-p, e+p, n+p }')
          pmtiles extract "$region" "$work/tiles.pmtiles" --bbox="$sub" --maxzoom=15 >/dev/null 2>&1 \
            && base64 -w0 "$work/tiles.pmtiles" > "$work/tiles.b64"
        else
          echo "health: no map yet. Run health-map once to add one." >&2
        fi
      fi

      out="''${XDG_RUNTIME_DIR:-/tmp}/health.html"
      umask 077
      {
        sed '/<!--LIBS-->/,$d' ${page}
        printf '<style>\n'; cat ${maplibreCss}; printf '</style>\n<script>\n'
        cat ${maplibreJs} ${pmtilesJs} ${basemapsJs}
        printf '</script>\n'
        sed -n '/<!--LIBS-->/,/<!--DATA-->/p' ${page} | sed '1d;$d'
        # </ escaped so a workout name can't close the script tag.
        printf '<script type="application/json" id="data">'; sed 's#</#<\\/#g' "$work/data.json"; printf '</script>\n'
        printf '<script type="text/plain" id="maptiles">'; cat "$work/tiles.b64"; printf '</script>\n'
        sed '1,/<!--DATA-->/d' ${page}
      } > "$out"
      exec firefox --new-window "file://$out"
    '';
  };

  health-map = pkgs.writeShellApplication {
    name = "health-map";
    runtimeInputs = with pkgs; [ pmtiles curl coreutils gawk ];
    text = ''
      bbox=$(${fit2json} "$HOME/sync" --bbox) || { echo "health-map: no activities with GPS in ~/sync yet" >&2; exit 1; }
      # About 10 km of margin, so nearby new routes are covered too.
      IFS=, read -r w s e n <<< "$bbox"
      area=$(awk -v w="$w" -v s="$s" -v e="$e" -v n="$n" 'BEGIN { printf "%f,%f,%f,%f", w-0.1, s-0.1, e+0.1, n+0.1 }')

      # Protomaps publishes a daily build and keeps about a week of them.
      url=""
      for d in 0 1 2 3 4 5 6; do
        try="https://build.protomaps.com/$(date -d "-$d day" +%Y%m%d).pmtiles"
        if curl -fsI -o /dev/null "$try"; then url=$try; break; fi
      done
      [ -n "$url" ] || { echo "health-map: no Protomaps build found in the last week" >&2; exit 1; }

      mkdir -p "${mapDir}"
      echo "Downloading the map around your activities from $url (via Mullvad)…"
      pmtiles extract "$url" "${mapDir}/region.pmtiles.new" --bbox="$area" --maxzoom=15
      mv "${mapDir}/region.pmtiles.new" "${mapDir}/region.pmtiles"
      printf '%s\n' "$area" > "${mapDir}/region.bbox"
      echo "Done: $(du -h "${mapDir}/region.pmtiles" | cut -f1). Run health."
    '';
  };
in
{
  home.packages = [ health health-map ];
  xdg.desktopEntries.health = {
    name = "Health";
    exec = "health";
    icon = "applications-science";
    comment = "Gadgetbridge data from the phone, as charts";
    categories = [ "Utility" ];
  };
}
