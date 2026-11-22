# Super + K: a list of commands you run by hand now and then. Pick one and
# it's copied, to paste into a terminal (and edit, for the <placeholders>).
# Updates and server deploys are in the bar's update dropdown instead
# (updateCommands in quickshell.nix).
{ pkgs, ... }:
let
  quickCommands = pkgs.writeShellApplication {
    name = "quick-commands";
    runtimeInputs = with pkgs; [ fuzzel wl-clipboard ];
    text = ''
      # shellcheck disable=SC2088  # the ~ is for the terminal you paste into
      pick=$(printf '%s\n' \
        "copper pull" \
        "copper done" \
        "sudo yubikey-away" \
        "cd ~/drop && push" \
        "sudo wifi-to-host" \
        "cd ~/fox-den && ./deploy.sh <host> test" \
        "cd ~/fox-den && ./secret.sh <host> <name>" \
        | fuzzel --dmenu --prompt "copy › " --width 60 --lines 7) || exit 0
      printf '%s' "$pick" | wl-copy
      qs-island flash copied || true   # the bar may not be running
    '';
  };
in
{
  home.packages = [ quickCommands ];
}
