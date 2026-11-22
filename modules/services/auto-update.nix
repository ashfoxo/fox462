# Update check for the laptop: every 6 hours and 5 minutes after boot, as
# arlo (never root), it asks whether nixpkgs or home-manager have moved and
# pings you if they have. It builds nothing and never touches the repo; the
# new lock goes to a scratch file. Update yourself when it suits you: click
# the bar's update icon and copy the command (updateCommands in
# home/desktop/quickshell.nix). Skipped while there's no network.
#
# Try it now: sudo systemctl start nixos-update, then journalctl -u nixos-update
# The bar's update item reads /var/lib/nixos-update (UnitStatus in
# home/desktop/quickshell/StatusItems.qml).
{ config, pkgs, lib, ... }:

let
  user = "arlo";
  repo = "/home/${user}/fox-den";
  dir = "/var/lib/nixos-update";

  script = pkgs.writeShellApplication {
    name = "nixos-update";
    runtimeInputs = with pkgs; [ coreutils jq config.nix.package networkmanager libnotify ];
    text = ''
      dir=${dir}

      # result <state> <text>: what the bar shows. States: ok, uptodate, skipped, failed.
      result() { printf '%s %s\n' "$1" "$2" > "$dir/result"; }
      set -E
      trap 'result failed "update check failed, see journalctl -u nixos-update"' ERR

      notify() {
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
          notify-send -a "Update" "$1" "$2" || true
      }

      if ! nm-online -q -t 60; then
        result skipped "no network"
        exit 0
      fi

      nix flake update --flake ${repo} --output-lock-file "$dir/flake.lock.new"

      # Of the inputs that ship software, the ones whose revision moved. The
      # rest (nixpkgs-unstable, tooling, inputs' own inputs) move constantly.
      changed=$(jq -rn --slurpfile old ${repo}/flake.lock --slurpfile new "$dir/flake.lock.new" '
        [ "nixpkgs", "home-manager"
          | select($new[0].nodes[.].locked.rev != $old[0].nodes[.].locked.rev) ] | join(" ")')

      touch "$dir/last-success"
      if [ -z "$changed" ]; then
        result uptodate "nothing new"
        exit 0
      fi
      result ok "updates: $changed"
      # Ping once per new set of updates, not every 6 hours.
      if [ "$changed" != "$(cat "$dir/notified" 2>/dev/null)" ]; then
        notify "Updates available" "$changed"
        printf '%s' "$changed" > "$dir/notified"
      fi
    '';
  };
in
{
  systemd.services.nixos-update = {
    description = "Check whether the flake inputs have updates";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment.HOME = "/home/${user}";
    serviceConfig = {
      Type = "oneshot";
      User = user;
      ExecStart = lib.getExe script;
      StateDirectory = "nixos-update";
      StateDirectoryMode = "0755";
    };
  };

  systemd.timers.nixos-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "0/6:00";
      OnBootSec = "5min";  # after the reboot that applies an update, the bar stops saying "updates available"
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}
