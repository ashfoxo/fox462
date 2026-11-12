# `health`: your watch data as one page, with no server. build.py reads the
# newest database the phone exports anywhere under ~/sync (Gadgetbridge →
# Settings → Automations → auto export) and the workout FIT/GPX files (auto
# FIT/GPX export, and those inside its ZIP exports), fills older days from the
# Garmin backfill (health-backfill), writes the page into
# $XDG_RUNTIME_DIR/health (RAM) and opens it as an app window in its own
# ungoogled-chromium sandbox, which has no network and sees only that folder.
# Workout files are parsed once and cached in ~/.local/share/health/cache.
# The page makes no network requests: the map libraries are inlined, and the
# map tiles come from the local region file.
#
# `health-map`: downloads the OpenStreetMap area around your activities (from
# Protomaps' daily build) into ~/.local/share/health. The one step that goes
# online; the server sees the area you ask for, via Mullvad. Run it once, and
# again when you've been active somewhere new (`health` tells you).
{ pkgs, nixpak, osConfig, ... }:
let
  # Shown in a sandboxed ungoogled-chromium with no network (sandboxes.nix).
  viewer = (import ../sandboxes.nix {
    inherit pkgs nixpak;
    extraGpuDev = osConfig.fox.desktop.sandboxGpuDevices;
    extraGpuEnv = osConfig.fox.desktop.sandboxGpuEnv;
  }).health-view;
  c = (import ../../../lib/palette.nix).for "quickshell";
  page = pkgs.replaceVars ./page.html {
    inherit (c) bg surf line fg dim faint;
    accent = c.forest_text;
    teal = c.teal_text;
    rust = c.rust_text;
    inherit (c) amber;
  };

  # Pinned map libraries, inlined into the page.
  lib = { url, hash }: pkgs.fetchurl { inherit url hash; };
  maplibreJs = lib { url = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"; hash = "sha256-vpYzxNhw4m+zfxz+XFp3GBZnEUAD6hYgeseFDY2ordE="; };
  maplibreCss = lib { url = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css"; hash = "sha256-V2sIX92Uh6ZaGSFTKMHghsB85b9toJtmazgG09AI2uk="; };
  pmtilesJs = lib { url = "https://unpkg.com/pmtiles@3.2.1/dist/pmtiles.js"; hash = "sha256-NnwZ+JNtHWwbGCCw3uBT95P8KSd2VcPkcfXtTTe18EU="; };
  basemapsJs = lib { url = "https://unpkg.com/@protomaps/basemaps@5.1.0/dist/basemaps.js"; hash = "sha256-OX3U/ZCryYv6vN8tB0Q2I2G1SIRNabrn955/5vG7NcE="; };

  python = pkgs.python3.withPackages (p: [ p.fitdecode ]);
  build = "${python}/bin/python3 -I ${./build.py}";
  mapDir = "$HOME/.local/share/health";

  health = pkgs.writeShellApplication {
    name = "health";
    runtimeInputs = with pkgs; [ pmtiles ];
    text = ''
      dir="$XDG_RUNTIME_DIR/health"   # RAM; the viewer sees it as /health
      mkdir -p "$dir"
      ${build} "$dir/index.html" ${page} ${maplibreCss} ${maplibreJs} ${pmtilesJs} ${basemapsJs}
      exec ${viewer}/bin/chromium --app=file:///health/index.html \
        --no-first-run --no-default-browser-check --password-store=basic
    '';
  };

  health-map = pkgs.writeShellApplication {
    name = "health-map";
    runtimeInputs = with pkgs; [ pmtiles curl coreutils gawk ];
    text = ''
      bbox=$(${build} --bbox) || exit 1
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
  # `health-backfill`: one-off copy of your Garmin Connect history through
  # Garmin's Personal API, into ~/.local/share/health/garmin (persisted, so in
  # restic). Resumable; run again if it stops. Delete the key on Garmin's
  # Personal API Key page once it's done.
  health-backfill = pkgs.writeShellApplication {
    name = "health-backfill";
    runtimeInputs = with pkgs; [ pass ];
    text = ''
      # The key goes to the script on stdin, never in argv or the environment.
      pass show garmin/personal-api-key | head -n1 \
        | ${pkgs.python3}/bin/python3 -I ${./backfill.py} "${mapDir}/garmin" "$@"
    '';
  };
in
{
  home.packages = [ health health-map health-backfill ];
  xdg.desktopEntries.health = {
    name = "Health";
    exec = "health";
    icon = "applications-science";
    comment = "Gadgetbridge data from the phone, as charts";
    categories = [ "Utility" ];
  };
}
