# Syncthing: always-on copy of the Minecraft instances and of ~/sync.
{ config, pkgs, lib, inputs, srv, ... }:
let
  folders = config.services.syncthing.settings.folders;
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
  # lib/syncthing.nix gives it). Two machines dialling each other at once
  # breaks the connection, see the note at the top of lib/syncthing.nix.
  #
  # The same goes for ~/sync, which the phone has too: the phone syncs with
  # the computers directly when they're on, and with fox-red always.
  #
  # Runs as the syncthing system user; the files are in
  # /var/lib/syncthing/minecraft-instances and /var/lib/syncthing/sync.
  # Nobody works on them here: it only passes on what the others send.
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
        devices = lib.mapAttrs (_: d: {
          id = d.id;
          addresses = [ "dynamic" ];
        }) peers;

        folders.minecraft-instances = {
          id = "minecraft-instances";
          label = "Minecraft instances";
          path = "${config.services.syncthing.dataDir}/minecraft-instances";
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
          devices = sharing "sync";
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };

        options = {
          localAnnounceEnabled = false;
          globalAnnounceEnabled = false;
          relaysEnabled = false;
          natEnabled = false;
          urAccepted = -1;
        };
      };
    };

  # Syncthing's sync port, open to NetBird peers only.
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 22000 ];
}
