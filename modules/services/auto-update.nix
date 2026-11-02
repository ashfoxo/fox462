# Unattended updates for the laptop, on the backup's schedule (daily, with up
# to an hour of random delay, and at the next boot if the machine was off).
#
# Each run, as root, in /home/arlo/fox-den:
#   1. Does nothing on a metered network (mark your phone hotspot with
#      `nmcli connection modify "<name>" connection.metered yes`), without a
#      network, or while the repo has uncommitted edits.
#   2. `nix flake update`, as arlo, so no root-owned files appear in the repo.
#   3. `nixos-rebuild boot`: builds, and makes it the next boot's default. It is
#      never switched to while you work.
#   4. Commits flake.lock as "Update <date>" with the package changes (`nvd`) in
#      the message. It does NOT push; do that by hand: git push origin main.
# A failed build puts flake.lock back. The previous boot entries stay.
#
# Try it now: sudo systemctl start nixos-update, then journalctl -u nixos-update
# The bar's update item (home/desktop/quickshell/Update.qml) reads /var/lib/nixos-update.
{ config, pkgs, lib, ... }:

let
  user = "arlo";
  repo = "/home/${user}/fox-den";
  host = config.fox.machine;
  dir = "/var/lib/nixos-update";

  script = pkgs.writeShellApplication {
    name = "nixos-update";
    runtimeInputs = with pkgs; [
      coreutils gnugrep gnused git config.nix.package nixos-rebuild nvd
      util-linux systemd networkmanager libnotify
    ];
    text = ''
      repo=${repo}
      dir=${dir}

      # Run as arlo, with arlo's home so git finds the author and nix its cache.
      as_user() { runuser -u ${user} -- env HOME=/home/${user} "$@"; }

      # result <state> <text>: what the bar shows. States: ok, uptodate, skipped, failed.
      result() { printf '%s %s\n' "$1" "$2" > "$dir/result"; }

      # notify <title> <text>: a desktop notification, if arlo is logged in.
      notify() {
        uid=$(id -u ${user})
        as_user env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
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
        result failed "no network"
        exit 1
      fi

      if [ ! -d "$repo/.git" ]; then
        result failed "no git repo at $repo"
        exit 1
      fi

      if [ -n "$(as_user git -C "$repo" status --porcelain)" ]; then
        result skipped "uncommitted edits in the repo"
        exit 0
      fi

      as_user nix flake update --flake "$repo"

      if as_user git -C "$repo" diff --quiet -- flake.lock; then
        result uptodate "nothing new"
        touch "$dir/last-success"
        exit 0
      fi

      if ! nixos-rebuild boot --flake "$repo#${host}" 2>&1 | tee "$dir/build.log"; then
        as_user git -C "$repo" checkout -- flake.lock
        err=$(grep -iE 'error' "$dir/build.log" | tail -n1 || true)
        result failed "''${err:-build failed, see journalctl -u nixos-update}"
        notify "Update failed" "''${err:-see journalctl -u nixos-update}"
        exit 1
      fi

      diff=$(nvd diff /run/current-system /nix/var/nix/profiles/system | sed 's/\x1b\[[0-9;]*m//g')

      as_user git -C "$repo" add flake.lock
      if ! as_user git -C "$repo" commit -q -m "Update $(date +%F)" -m "$diff"; then
        result failed "built, but the commit failed"
        notify "Update built" "The commit failed; flake.lock is changed but not committed."
        exit 1
      fi

      result ok "ready for the next boot"
      touch "$dir/last-success"
      notify "Update ready" "Applies at the next reboot. Push with: git push origin main"
    '';
  };
in
{
  # nixos-rebuild runs as root and reads arlo's repo; git refuses that without this.
  programs.git = {
    enable = true;
    config.safe.directory = [ repo ];
  };

  systemd.services.nixos-update = {
    description = "Update flake inputs and build the next boot's system";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment.HOME = "/root";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe script;
      StateDirectory = "nixos-update";
      StateDirectoryMode = "0755";
      Restart = "on-failure";
      RestartSec = "10min";
    };
    unitConfig = {
      StartLimitIntervalSec = "6h";
      StartLimitBurst = 5;
    };
  };

  # Same schedule as the backup (restic.nix).
  systemd.timers.nixos-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
