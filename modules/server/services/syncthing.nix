# Syncthing: always-on copy of the Minecraft instances and of ~/sync, and the
# drop folder new media arrives through.
{ config, lib, pkgs, ... }:
let
  folders = config.services.syncthing.settings.folders;
  # On the Storage Box (music.nix), so a dropped movie can't fill the VPS disk.
  drop = "/mnt/music/drop";
  self = config.networking.hostName;
  all = import ../../../lib/syncthing.nix;

  # Every other device with an ID that pairs with this server (a device
  # with onlyWith pairs only with the machines it names).
  peers = lib.filterAttrs
    (name: d: name != self && d.id != "" && (!(d ? onlyWith) || lib.elem self d.onlyWith))
    all;

  # The peers that have a given folder.
  sharing = folder: lib.attrNames (lib.filterAttrs (_: d: lib.elem folder d.folders) peers);
in
{
  fox.server.backup = {
    # The synced Minecraft instances (worlds, mods, configs) and ~/sync, read
    # from the folders' own settings so the two can't point at different places.
    paths = [ folders.minecraft-instances.path folders.sync.path ];
    # Syncthing's own copies of changed and deleted files. restic's nightly
    # snapshots already keep the history, so these would only be stored twice.
    exclude = [ "${folders.minecraft-instances.path}/.stversions" "${folders.sync.path}/.stversions" ];
  };

  # The always-on copy of Prism Launcher's instances, so the laptop and the
  # desktop sync through fox-red even when they are never on at the same
  # time. Same folder, same rules as home/desktop/syncthing.nix; devices are
  # in lib/syncthing.nix.
  #
  # fox-red only accepts: the laptop and desktop dial its NetBird address,
  # and it dials nobody (every peer is "dynamic" here, whatever address
  # lib/syncthing.nix gives it). The one exception is fox-grey, off NetBird,
  # which it dials through fox-green's relay. Two machines dialling each other at once
  # breaks the connection, see the note at the top of lib/syncthing.nix.
  #
  # The same goes for ~/sync, which the phone has too: the phone syncs with
  # the computers directly when they're on, and with fox-red always.
  #
  # Runs as the syncthing system user; the files are in
  # /var/lib/syncthing/minecraft-instances and /var/lib/syncthing/sync,
  # encrypted: fox-red is an untrusted device (lib/syncthing.nix) and never
  # has the folder passwords. It only passes on what the
  # others send, and its backups hold ciphertext too.
  # Switching a folder to or from receiveencrypted on a running server needs
  # the folder deleted first (DELETE /rest/config/folders/<id>, then let
  # syncthing-init re-add it): Syncthing refuses to change the type in place,
  # and syncthing-init retries forever.
  # Web UI: ssh -L 8384:localhost:8384 fox-red, then http://localhost:8384.
  # Logs: journalctl -u syncthing
  services.syncthing =
    {
      enable = true;
      # GUI on localhost only (the default); no ports opened by the module.
      guiAddress = "127.0.0.1:8384";
      openDefaultPorts = false;

      overrideDevices = true;
      overrideFolders = true;

      settings = {
        # Wait for every peer to dial in, except one on the relay (fox-grey),
        # which this server dials (lib/syncthing.nix).
        devices = lib.mapAttrs (_: d: {
          id = d.id;
          addresses = if d ? relay then [ d.relay ] else [ "dynamic" ];
        }) peers;

        folders.minecraft-instances = {
          id = "minecraft-instances";
          label = "Minecraft instances";
          path = "${config.services.syncthing.dataDir}/minecraft-instances";
          type = "receiveencrypted";  # ciphertext only
          devices = sharing "minecraft-instances";
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };

        folders.sync = {
          id = "sync";
          label = "sync";
          path = "${config.services.syncthing.dataDir}/sync";
          type = "receiveencrypted";
          devices = sharing "sync";
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };

        # The drop folder: media you add on the laptop (~/drop), in plain
        # form, since fox-red has to read it. Receive-only, and deletions from
        # the laptop are ignored, so the laptop can empty its copy whenever it
        # likes; drop-sort below moves things out once they've fully arrived.
        folders.drop = {
          id = "drop";
          label = "drop";
          path = drop;
          type = "receiveonly";
          devices = sharing "drop";
          ignoreDelete = true;
          ignorePerms = true;   # CIFS: the mount sets every file's mode
        };

        options = {
          localAnnounceEnabled = false;
          globalAnnounceEnabled = false;
          # On only to dial relay:// peers (fox-grey). Listening is TCP only,
          # so the server never joins a public relay pool.
          relaysEnabled = lib.any (d: d ? relay) (lib.attrValues peers);
          listenAddresses = [ "tcp://:22000" ];
          natEnabled = false;
          urAccepted = -1;
        };
      };
    };

  # Syncthing's sync port, open to NetBird peers only.
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 22000 ];

  # The drop folder is on the navidrome-owned CIFS mount.
  users.users.syncthing.extraGroups = [ "navidrome" ];
  systemd.services.syncthing.unitConfig.RequiresMountsFor = "/mnt/music";

  # Nightly: once nothing is still arriving, move
  # each drop subfolder to where its app reads it. A server-side rename, same
  # share. Half-arrived albums wait for the next night.
  systemd.services.drop-sort = {
    description = "Move what arrived in the drop folder to the music, audiobook and video folders";
    after = [ "syncthing.service" "remote-fs.target" ];
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };
    serviceConfig.Type = "oneshot";
    environment.RCLONE_CONFIG = "/dev/null";
    path = with pkgs; [ curl jq gnugrep rclone coreutils ];
    script = ''
      set -euo pipefail
      key=$(grep -oP '(?<=<apikey>)[^<]+' ${config.services.syncthing.configDir}/config.xml)
      need=$(curl -fsS -H "X-API-Key: $key" "http://${config.services.syncthing.guiAddress}/rest/db/status?folder=drop" | jq .needTotalItems)
      if [ "$need" != 0 ]; then
        echo "$need item(s) still arriving; trying again tomorrow"
        exit 0
      fi
      move() {
        [ -d "${drop}/$1" ] || return 0
        mkdir -p "$2"
        rclone move "${drop}/$1" "$2" --delete-empty-src-dirs --exclude '.syncthing.*'
      }
      move Music /mnt/music/library   # already tagged in Picard on the laptop
      move Audiobooks /mnt/music/spoken/Audiobooks
      move Movies /mnt/music/video/Movies
      move TV /mnt/music/video/TV
    '';
  };
  systemd.timers.drop-sort = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };
  fox.server.monitoring.alertOnFailure.drop-sort.title = "drop sort FAILED";
}
