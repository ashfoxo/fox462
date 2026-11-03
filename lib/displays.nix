# Where the main-display choice lives. Shared by home/desktop/displays.nix
# (the picker writes it), quickshell.nix (the bar reads it and writes the
# lock file) and lockscreen.nix (hyprlock reads the lock file).
# Takes the home directory; kept across reboots by modules/ephemeral-home.nix.
home: rec {
  dir = "${home}/.local/state/fox-displays";

  # The chosen display's description as Hyprland gives it ("Hewlett Packard
  # HP 2311 CNT141G1KZ"), so the choice follows that screen to any port.
  # Empty or missing: automatic.
  choice = "${dir}/main";

  # One line, `$main = <port>`, for the screen the bar is on right now.
  # hyprlock sources it to put its clock and prompt on that screen.
  lock = "${dir}/hyprlock.conf";
}
