{ pkgs, config, ... }:

# The main display: the screen with the bar, the notification popups and the
# lock screen's clock and prompt.
#
# Super + Shift + P opens a list of the connected displays (display-main).
# Picking one saves its description, so it becomes the main display again
# whenever it's plugged in, on whichever port. "automatic" clears the choice.
#
# How a screen is picked, first match wins:
#   1. the display chosen here, if it's connected
#   2. fox.desktop.barMonitors (per host), if one of them is connected
#   3. the laptop panel, else any screen
# The bar does the picking (quickshell/shell.qml) and moves as soon as the
# choice or the connected screens change. It also writes the result to the
# lock file, which hyprlock reads each time it starts (lockscreen.nix).
#
# Where new displays go (right of the laptop by default) is the catch-all
# monitor rule in hyprland.nix; per-host rules are fox.desktop.monitors.

let
  files = import ../../lib/displays.nix config.home.homeDirectory;

  displayMain = pkgs.writeShellApplication {
    name = "display-main";
    runtimeInputs = with pkgs; [ coreutils jq fuzzel hyprland ];
    text = ''
      mkdir -p ${files.dir}
      current=$(cat ${files.choice} 2>/dev/null || true)
      monitors=$(hyprctl monitors -j)

      # Line 0 is "automatic"; line N is monitor N-1. The current choice is
      # marked with a dot.
      menu=$(
        if [ -z "$current" ]; then echo "• automatic"; else echo "  automatic"; fi
        jq -r --arg cur "$current" \
          '.[] | (if .description == $cur then "• " else "  " end) + "\(.name)  \(.description)"' \
          <<<"$monitors"
      )

      pick=$(fuzzel --dmenu --index --prompt "main display › " --width 70 --lines 6 <<<"$menu") || exit 0

      if [ "$pick" = 0 ]; then
        choice=""
      else
        choice=$(jq -r --argjson i "$((pick - 1))" '.[$i].description' <<<"$monitors")
      fi

      # Written whole and renamed into place, so the bar never reads half a file.
      printf '%s\n' "$choice" > ${files.choice}.tmp
      mv ${files.choice}.tmp ${files.choice}
    '';
  };
in
{
  home.packages = [ displayMain ];

  # The folder for the choice and the lock file. On the laptop and desktop it
  # is also kept across reboots (modules/ephemeral-home.nix).
  systemd.user.tmpfiles.rules = [ "d ${files.dir} 0700 - - -" ];
}
