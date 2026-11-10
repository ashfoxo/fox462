# Update check for the laptop: every 6 hours, as arlo (never root), it asks
# whether the flake's inputs have moved and pings you if they have. It builds
# nothing and never touches the repo; the new lock goes to a scratch file.
# Update yourself when it suits you:
#   cd ~/fox-den && nix flake update && sudo nixos-rebuild boot --flake .#fox-amber
#
# Skips metered networks (mark your hotspot with
# `nmcli connection modify "<name>" connection.metered yes`) and no network.
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
    runtimeInputs = with pkgs; [ coreutils jq config.nix.package systemd networkmanager libnotify ];
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

      # Metered: 1 = yes, 3 = guessed yes.
      metered=$(busctl get-property org.freedesktop.NetworkManager \
        /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered \
        | cut -d' ' -f2 || echo 0)
      case "$metered" in
        1|3) result skipped "metered network"; exit 0 ;;
        *) ;;
      esac
      if ! nm-online -q -t 60; then
        result skipped "no network"
        exit 0
      fi

      nix flake update --flake ${repo} --output-lock-file "$dir/flake.lock.new"

      # Inputs whose locked revision moved, e.g. "nixpkgs home-manager".
      changed=$(jq -rn --slurpfile old ${repo}/flake.lock --slurpfile new "$dir/flake.lock.new" '
        [ $new[0].nodes | to_entries[] | select(.value.locked)
          | select(.value.locked.rev != $old[0].nodes[.key].locked.rev) | .key ] | join(" ")')

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
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}
