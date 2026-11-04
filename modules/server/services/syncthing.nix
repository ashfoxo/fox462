# Syncthing: always-on copy of the Minecraft instances.
{ config, pkgs, lib, inputs, srv, ... }:
{
  fox.server.backup = {
    # The synced Minecraft instances (worlds, mods, configs), read from the
    # folder's own setting so the two can't point at different places.
    paths = [ config.services.syncthing.settings.folders.minecraft-instances.path ];
    # Syncthing's own copies of changed and deleted files. restic's nightly
    # snapshots already keep the history, so these would only be stored twice.
    exclude = [ "${config.services.syncthing.settings.folders.minecraft-instances.path}/.stversions" ];
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
  # Runs as the syncthing system user; the files are in
  # /var/lib/syncthing/minecraft-instances. Nothing plays here, so nothing
  # changes here: it only passes on what the others send.
  # Web UI: ssh -L 8384:localhost:8384 fox-red, then http://localhost:8384.
  # Logs: journalctl -u syncthing
  services.syncthing =
    let
      peers = lib.filterAttrs (name: d: name != config.networking.hostName && d.id != "")
        (import ../../../lib/syncthing.nix);
    in
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
          devices = lib.attrNames peers;
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
