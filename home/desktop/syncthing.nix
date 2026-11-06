{ lib, config, osConfig, ... }:

# Syncthing, directly over NetBird, for two folders:
#   - Prism Launcher's instances (worlds, mods, configs, resource packs), the
#     same on every personal machine. Logins, Java and caches stay per machine.
#   - ~/sync: anything to have on every device, the phone included (it syncs
#     with every machine directly, and fox-red keeps an always-on copy).
#     Sandboxed apps can't see it; copy files in and out of their own shared
#     folders.
#
# Don't play the same world on two machines at once: both copies would
# change, and Syncthing keeps the loser as a *.sync-conflict-* file.
#
# Devices and their NetBird addresses: lib/syncthing.nix. Each machine
# syncs with every other machine listed there that has an ID, fox-red
# included: the server is always on, so the laptop and desktop sync
# through it even when they're never on at the same time.
# Web UI: http://localhost:8384. Logs: journalctl --user -u syncthing

let
  self = osConfig.fox.machine;

  # Every other device that has an ID yet and pairs with this machine.
  peers = lib.filterAttrs
    (name: d: name != self && d.id != "" && (!(d ? onlyWith) || lib.elem self d.onlyWith))
    (import ../../lib/syncthing.nix);

  # The peers that have a given folder.
  sharing = folder: lib.attrNames (lib.filterAttrs (_: d: lib.elem folder d.folders) peers);

  # The same, as Syncthing wants them: an untrusted peer (fox-red) gets the
  # folder encrypted with its password (lib/syncthing.nix, AUDIT.md C10).
  shareWith = folder: map (name:
    if peers.${name}.untrusted or false then {
      inherit name;
      encryptionPasswordFile = osConfig.sops.secrets."syncthing-${folder}-password".path;
    } else name) (sharing folder);

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
        devices = shareWith "minecraft-instances";
        # The last 5 versions of a changed or deleted file are kept in
        # instances/.stversions, in case a sync goes the wrong way.
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };

      folders.sync = {
        id = "sync";
        label = "sync";
        path = "${config.home.homeDirectory}/sync";
        devices = shareWith "sync";
        # The last 5 versions of a changed or deleted file are kept in
        # ~/sync/.stversions.
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
