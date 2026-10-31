{ lib, config, osConfig, ... }:

# Syncthing: keeps Prism Launcher's instances (worlds, mods, configs,
# resource packs) the same on every personal machine, directly over
# NetBird. Logins, Java and caches stay per machine.
#
# Don't play the same world on two machines at once: both copies would
# change, and Syncthing keeps the loser as a *.sync-conflict-* file.
#
# Devices and their NetBird addresses: lib/syncthing.nix. Each machine
# syncs with every other machine listed there that has an ID.
# Web UI: http://localhost:8384. Logs: journalctl --user -u syncthing

let
  self = osConfig.fox.machine;

  # Every other host that has an ID yet.
  peers = lib.filterAttrs (name: d: name != self && d.id != "")
    (import ../../lib/syncthing.nix);

  # Prism runs sandboxed (sandboxes.nix): its home is this folder.
  prism = "${config.home.homeDirectory}/.local/share/sandboxes/prismlauncher/.local/share/PrismLauncher";
in
{
  services.syncthing = {
    enable = true;

    # The config here is the whole truth: devices or folders added in the
    # web UI are removed again on the next start.
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = lib.mapAttrs (_: d: {
        id = d.id;
        # No address: wait for that device to connect (lib/syncthing.nix).
        addresses = if d.address == "" then [ "dynamic" ] else [ "tcp://${d.address}:22000" ];
      }) peers;

      folders.minecraft-instances = {
        id = "minecraft-instances";
        label = "Minecraft instances";
        path = "${prism}/instances";
        devices = lib.attrNames peers;
        # The last 5 versions of a changed or deleted file are kept in
        # instances/.stversions, in case a sync goes the wrong way.
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };

      options = {
        # NetBird only: nothing announced to the LAN or the internet, no
        # relays. Peers are found at the addresses above.
        localAnnounceEnabled = false;
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1; # no usage reporting
      };
    };
  };
}
