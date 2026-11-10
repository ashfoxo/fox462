# `pack` before a trip, `unpack` after. Both need sudo.
#
#   pack    snapshots your persisted home folders to the restic repo (tag
#           "pack"), empties them, and powers off. Apps start logged out and
#           Documents etc. are empty, so an unlock shows little.
#   unpack  empties them again (anything from the trip goes), restores the
#           pack snapshot, and reboots.
#
# What stays on the laptop is `keep` below. Everything else in
# ephemeral-home.nix's list is packed, so a folder added there later is packed
# by default.
#
# Syncthing's own state is packed too: the laptop comes back with a new device
# ID that fox-red and the phone don't accept. Otherwise the emptied ~/sync
# would look like "everything was deleted" and wipe the other devices.
#
# shortcut: the laptop still holds the restic password and S3 key while
# travelling, so whoever gets it unlocked AND acts on its credentials can read
# the repo. Fix: a travel boot without those secrets, if a trip ever needs it.
{ config, lib, pkgs, ... }:
let
  home = "/persist/home/arlo";
  marker = "/persist/travel-packed";

  # Stays on the laptop while packed.
  keep = [
    "fox-den" ".ssh" ".gnupg" ".password-store" ".config/Yubico"
    ".config/Bitwarden" ".config/Notesnook"
    ".claude"   # on disk by choice (ephemeral-home.nix)
    ".config/helix" ".local/share/direnv" ".local/state/fox-displays" ".local/share/whisper"
    ".local/share/Steam" ".steam"
    # Not in any backup (restic.nix excludes them), so packing would lose them.
    "media" "working" "torrents"
  ];

  persisted = map (d: d.directory or d) config.environment.persistence."/persist".users.arlo.directories;
  packed = map (d: "${home}/${d}") (lib.subtractLists keep persisted);

  backup = config.services.restic.backups.s3;
  restic = ''
    set -a; . ${backup.environmentFile}; set +a
    export RESTIC_REPOSITORY=${backup.repository} RESTIC_PASSWORD_FILE=${backup.passwordFile}
  '';
  paths = lib.escapeShellArgs packed;

  # Run as a system unit: it ends arlo's session, which would kill a script
  # started from arlo's terminal.
  wipe = ''
    systemctl stop "user@$(id -u arlo).service"
    for p in ${paths}; do [ -d "$p" ] && find "$p" -mindepth 1 -delete; done
  '';

  pack = pkgs.writeShellApplication {
    name = "pack";
    runtimeInputs = [ pkgs.restic pkgs.systemd ];
    # SC1091: the env file exists only at runtime. SC2016: the quotes delay
    # expansion to the shell systemd-run starts, on purpose.
    excludeShellChecks = [ "SC1091" "SC2016" ];
    text = ''
      [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
      [ ! -e ${marker} ] || { echo "already packed; unpack first" >&2; exit 1; }
      ${restic}
      read -rp "Close your apps first. Type pack to back up, empty and power off: " a
      [ "$a" = pack ] || exit 1
      restic backup --tag pack --exclude-caches ${paths}
      touch ${marker}
      systemd-run --unit=travel-pack --no-block bash -c ${lib.escapeShellArg (wipe + "systemctl poweroff")}
    '';
  };

  unpack = pkgs.writeShellApplication {
    name = "unpack";
    runtimeInputs = [ pkgs.restic pkgs.systemd ];
    # SC1091: the env file exists only at runtime. SC2016: the quotes delay
    # expansion to the shell systemd-run starts, on purpose.
    excludeShellChecks = [ "SC1091" "SC2016" ];
    text = ''
      [ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
      [ -e ${marker} ] || { echo "not packed" >&2; exit 1; }
      ${restic}
      restic snapshots --tag pack --latest 1
      read -rp "Anything saved on the trip in the packed folders is lost. Type unpack to restore and reboot: " a
      [ "$a" = unpack ] || exit 1
      # On failure the marker stays, so running unpack again retries.
      systemd-run --unit=travel-unpack --no-block bash -c ${lib.escapeShellArg (wipe + ''
        ${restic}
        ${pkgs.restic}/bin/restic restore latest --tag pack --target / && rm -f ${marker}
        systemctl reboot
      '')}
    '';
  };
in
{
  assertions = [{
    assertion = config.fox.backup.enable;
    message = "travel.nix needs the restic backup (fox.backup.enable).";
  }];
  environment.systemPackages = [ pack unpack ];
}
