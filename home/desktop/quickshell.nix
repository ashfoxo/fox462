{ pkgs, lib, config, osConfig, ... }:

# Desktop shell (Quickshell): the bar along the top of the screen and its
# dropdowns (chat, Mullvad, NetBird, backup, update, Wi-Fi, Bluetooth,
# volume, power), and the notification popups. Replaces Waybar and mako.
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
