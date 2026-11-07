{ pkgs, lib, config, osConfig, ... }:

# Desktop shell (Quickshell): the bar along the top of the screen and its
# dropdowns (chat, now playing, Mullvad, NetBird, backup, update, Wi-Fi,
# Bluetooth, volume, power), and the notification popups. Replaces Waybar and mako.
#
# The QML is in ./quickshell/ and gets copied into the Nix store together
# with Config.qml, which is GENERATED below from the settings in this file
# and palette.nix. Nothing reads ~/.config/quickshell, so the whole shell is
# rebuilt from this repo.
#
# Runs as a user service tied to the Hyprland session. A rebuild restarts
# it on the new files.
#   Logs:    journalctl --user -u quickshell -f
#   Restart: systemctl --user restart quickshell
# Docs: https://quickshell.org/docs/

let
  c = (import ../../lib/palette.nix).for "quickshell";
  user = config.home.username;
  displayFiles = import ../../lib/displays.nix config.home.homeDirectory;

  # ---------------------------------------------------------------------------
  # Settings (end up in Config.qml)
  # ---------------------------------------------------------------------------
  settings = {
    # Which monitor gets the bar when no main display is picked with
    # Super + Shift + P (displays.nix). The first one in the list that's
    # plugged in wins; if none are, the bar goes on the laptop screen, so an
    # empty list means "always the laptop". Each entry can be part of a
    # monitor's model (the "description" line of `hyprctl monitors all`,
    # e.g. "U2723QE"), which follows the screen to any port, or a port name
    # like "DP-1".
    # Per host: fox.desktop.barMonitors (modules/options.nix).
    barMonitors = osConfig.fox.desktop.barMonitors;

    # The main-display choice the bar reads, and the file it writes for the
    # lock screen (lib/displays.nix).
    displays = { inherit (displayFiles) choice lock; };

    # The prompt on the left: arlo@ws:~/web
    prompt = "${user}@${osConfig.fox.desktop.barHost}";

    # Workspace number -> name in the prompt. Matches the roles in
    # hypr/rules.lua. Unlisted workspaces show their number.
    workspaceNames = {
      "1" = "~";
      "2" = "web";
      "3" = "dev";
      "4" = "writing";
      "5" = "comms";
      "6" = "creative";
      "7" = "radio";
      "8" = "entertainment";
    };

    # Scratchpads: the tags after the prompt, and the chat apps behind
    # +chat. Shared with Hyprland's keys and rules, see scratchpads.nix.
    scratchpads = import ./scratchpads.nix;

    # Popups go after popupSeconds (critical ones stay until clicked). For
    # quietSeconds after a chat app opens, its notifications are dropped:
    # they're old messages arriving as it reconnects. The chat menu keeps
    # the newest `keep` messages.
    notifications = {
      popupSeconds = 5;
      quietSeconds = 120;
      maxPopups = 4;
      keep = 50;
    };

    # System load shows on the bar only past these. warn = amber, crit = rust.
    # CPU has to stay over the limit for `seconds` before it shows.
    load = {
      cpu  = { warn = 75; crit = 95; seconds = 10; };
      ram  = { warn = 80; crit = 92; };
      temp = { warn = 80; crit = 90; };   # °C
    };

    # Sizes. The font, gaps and dropdowns are proportioned for a 30px bar;
    # if you change the height, change the font size by about the same ratio.
    bar.height = 30;
    font = { family = "JetBrainsMono Nerd Font"; size = 16; };
    dropdown.width = 460;
    colors = lib.mapAttrs (_: hex: "#${hex}") c;

    scripts = {
      load = loadScript;
      unit = unitScript;
      nowplaying = nowPlayingScript;
      brightnessctl = lib.getExe pkgs.brightnessctl;
    };
  };

  # ---------------------------------------------------------------------------
  # Helper scripts (the bar runs these on a timer)
  # ---------------------------------------------------------------------------

  # CPU counters, memory and the hottest CPU sensor, one per line:
  #   cpu <total> <idle>    mem <total kB> <available kB>    temp <millidegrees>
  # The bar works out CPU % from the change between two runs.
  loadScript = lib.getExe (pkgs.writeShellApplication {
    name = "qs-load";
    runtimeInputs = with pkgs; [ coreutils gawk ];
    text = ''
      awk '/^cpu / { t = 0; for (i = 2; i <= NF; i++) t += $i; print "cpu", t, $5 + $6; exit }' /proc/stat
      awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { print "mem", t, a }' /proc/meminfo

      # CPU package sensor (Intel coretemp, AMD k10temp/zenpower), else the
      # hottest thermal zone.
      best=0
      for h in /sys/class/hwmon/hwmon*; do
        case "$(cat "$h/name" 2>/dev/null)" in
          coretemp|k10temp|zenpower|cpu_thermal) ;;
          *) continue ;;
        esac
        for t in "$h"/temp*_input; do
          [ -r "$t" ] || continue
          v=$(cat "$t"); [ "$v" -gt "$best" ] && best=$v
        done
      done
      if [ "$best" = 0 ]; then
        for t in /sys/class/thermal/thermal_zone*/temp; do
          [ -r "$t" ] || continue
          v=$(cat "$t"); [ "$v" -gt "$best" ] && best=$v
        done
      fi
      echo "temp $best"
    '';
  });

  # State of a timer-driven root job (the backup, the update) for the bar and
  # its dropdown: qs-unit <unit> <stamp file> [<result file>]. The stamp is
  # touched after each good run; the result file, if the job writes one, is
  # "<state> <note>" (modules/services/auto-update.nix). One per line:
  #   state ok|uptodate|running|skipped|failed|overdue|none|absent
  #   last  <unix time of the last good run, 0 if never>
  #   next  <unix time of the next scheduled run, 0 if unknown>
  #   note  <what the last run did or why it skipped>   (only with a result)
  #   error <the last error line>   (only when failed)
  # "absent": this machine doesn't have the unit.
  unitScript = lib.getExe (pkgs.writeShellApplication {
    name = "qs-unit";
    runtimeInputs = with pkgs; [ coreutils gnugrep systemd ];
    text = ''
      unit=$1 stamp=$2 resfile=''${3:-}
      if [ "$(systemctl show -p LoadState --value "$unit" 2>/dev/null)" != loaded ]; then
        printf 'state absent\nlast 0\nnext 0\n'
        exit 0
      fi

      last=0
      [ -e "$stamp" ] && last=$(stat -c %Y "$stamp")
      res=""
      [ -n "$resfile" ] && [ -e "$resfile" ] && res=$(cat "$resfile")
      rstate=''${res%% *}
      rnote=''${res#* }

      active=$(systemctl show -p ActiveState --value "$unit")
      sub=$(systemctl show -p SubState --value "$unit")
      result=$(systemctl show -p Result --value "$unit")
      if [ "$active" = activating ] && [ "$sub" != auto-restart ]; then state=running
      elif [ "$sub" = auto-restart ] || [ "$result" != success ] || [ "$rstate" = failed ]; then state=failed
      elif [ "$rstate" = skipped ]; then state=skipped
      elif [ "$last" = 0 ]; then state=none
      # Both are daily with up to 1h random delay, so allow 26h.
      elif [ $(( $(date +%s) - last )) -gt 93600 ]; then state=overdue
      elif [ "$rstate" = uptodate ]; then state=uptodate
      else state=ok
      fi
      echo "state $state"
      echo "last $last"

      # Empty or "n/a" when nothing is scheduled (and date -d "" would read
      # an empty string as today 00:00).
      next=$(systemctl show -p NextElapseUSecRealtime --value "$unit.timer" 2>/dev/null || true)
      if [ -n "$next" ] && [ "$next" != n/a ]; then
        echo "next $(date -d "$next" +%s 2>/dev/null || echo 0)"
      else
        echo "next 0"
      fi

      [ -n "$res" ] && echo "note $rnote"
      if [ "$state" = failed ]; then
        if [ "$rstate" = failed ]; then
          err=$rnote
        else
          err=$(journalctl -u "$unit" -n 200 -o cat --no-pager 2>/dev/null | grep -iE 'fatal|error' | tail -n1 || true)
        fi
        echo "error ''${err:-see journalctl -u $unit}"
      fi
    '';
  });

  # What you're playing on other devices, one JSON object per line:
  #   {"src":"music"|"spoken","title","artist","player","position","duration","cover"}
  # position is -1 when unknown (Navidrome doesn't report it). cover is a
  # local file, or "" if there's none. Each server is asked separately; one
  # that's unreachable (NetBird down) just adds nothing.
  # Credentials go to curl on stdin (-K -), so they never show in ps, and
  # covers are downloaded here so they never reach the bar either.
  nowPlayingScript = lib.getExe (pkgs.writeShellApplication {
    name = "qs-nowplaying";
    runtimeInputs = with pkgs; [ coreutils curl findutils jq ];
    text = ''
      # Covers, kept in RAM for 12h so a track's cover downloads once.
      dir="''${XDG_RUNTIME_DIR:-/tmp}/qs-nowplaying"
      mkdir -p "$dir"
      chmod 700 "$dir"
      find "$dir" -type f -mmin +720 -delete

      # cover <file name> <command...>: runs the command into the file unless
      # it's there already, then prints the file's path (nothing on failure).
      cover() {
        f="$dir/$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' _)"
        shift
        [ -s "$f" ] || { "$@" > "$f.tmp" && mv "$f.tmp" "$f"; } || rm -f "$f.tmp"
        if [ -s "$f" ]; then printf '%s' "$f"; fi
      }

      # ---- Navidrome ----
      # ND_USER and ND_PASSWORD.
      # shellcheck disable=SC1091
      . ${osConfig.sops.secrets.navidrome-user.path}
      salt=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
      token=$(printf '%s%s' "$ND_PASSWORD" "$salt" | md5sum | cut -d' ' -f1)
      auth="u=$(jq -rn --arg u "$ND_USER" '$u | @uri')&t=$token&s=$salt&v=1.16.1&c=quickshell"
      nd() {
        printf 'url = "https://music.emberfox.net/rest/%s?%s&%s"\n' "$1" "$auth" "$2" \
          | curl -sf --max-time 8 -K -
      }

      nd getNowPlaying f=json \
        | jq -c --arg u "$ND_USER" '."subsonic-response".nowPlaying.entry // [] | .[]
            | select(.username == $u)
            | {src: "music", title, artist: (.artist // ""), player: (.playerName // ""),
               position: -1, duration: (.duration // 0), art: (.coverArt // "")}' \
        | while IFS= read -r e; do
            art=$(jq -r .art <<<"$e")
            c=""
            if [ -n "$art" ]; then
              c=$(cover "nd-$art" nd getCoverArt "id=$(jq -rn --arg a "$art" '$a | @uri')&size=160") || c=""
            fi
            jq -c --arg c "$c" '.cover = $c | del(.art)' <<<"$e"
          done \
        || true

      # ---- Audiobookshelf ----
      abs_token=$(cat ${osConfig.sops.secrets.abs-token.path})
      abs() {
        printf 'url = "https://spoken.emberfox.net/api/%s"\nheader = "Authorization: Bearer %s"\n' "$1" "$abs_token" \
          | curl -sf --max-time 8 -K -
      }

      # Your open session isn't visible to a non-admin token, so: your newest
      # listening session, if a client synced it in the last 90s (they sync
      # every 10-15s while playing; a pause stops the syncs).
      abs 'me/listening-sessions?itemsPerPage=1' \
        | jq -c --argjson now "$(date +%s%3N)" '.sessions[0] // empty
            | select($now - .updatedAt < 90000)
            | {src: "spoken", title: .displayTitle, artist: (.displayAuthor // ""),
               player: (.deviceInfo.clientName // ""),
               position: (.currentTime // 0), duration: (.duration // 0),
               item: (.libraryItemId // "")}' \
        | while IFS= read -r e; do
            item=$(jq -r .item <<<"$e")
            c=""
            if [ -n "$item" ]; then
              c=$(cover "abs-$item" abs "items/$item/cover?width=160") || c=""
            fi
            jq -c --arg c "$c" '.cover = $c | del(.item)' <<<"$e"
          done \
        || true
    '';
  });

  # ---------------------------------------------------------------------------
  # The shell directory in the Nix store: ./quickshell/ plus Config.qml
  # ---------------------------------------------------------------------------
  configQml = pkgs.writeText "Config.qml" ''
    pragma Singleton
    import Quickshell

    // GENERATED by quickshell.nix from its settings and palette.nix.
    // Edit those, not this.
    Singleton {
    ${lib.concatStrings (lib.mapAttrsToList (n: v: "    readonly property var ${n}: ${builtins.toJSON v}\n") settings)}}
  '';

  shellDir = pkgs.runCommandLocal "quickshell-config" { } ''
    mkdir -p $out
    cp -r ${./quickshell}/. $out/
    cp ${configQml} $out/Config.qml
  '';
in
{
  home.packages = [ pkgs.quickshell ];

  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell desktop shell (bar and notifications)";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell --path ${shellDir}";
      Restart = "on-failure";
      RestartSec = 2;
      # The bar runs mullvad and netbird-wt0 (system) and voice-note (your
      # profile), and opens ghostty for nmtui and bluetui.
      Environment = [ "PATH=/run/wrappers/bin:/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin" ];
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}
