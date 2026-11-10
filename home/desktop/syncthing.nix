{ lib, config, osConfig, pkgs, ... }:

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
  # folder encrypted with its password (lib/syncthing.nix).
  shareWith = folder: map (name:
    if (peers.${name}.untrusted or false) && !(lib.elem folder (peers.${name}.plain or [ ])) then {
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

      # Drop media into ~/drop/{Music,Audiobooks,Movies,TV}: it goes to fox-red,
      # which files it nightly (server/services/syncthing.nix). Send-only, and
      # drop-clean below empties it, so nothing has to stay here.
      folders.drop = {
        id = "drop";
        label = "drop";
        path = "${config.home.homeDirectory}/drop";
        type = "sendonly";
        devices = shareWith "drop";
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

  # Daily: once fox-red has all of ~/drop, delete what's been here 3+ days.
  # The 3 days are for the Filen app's "Local backup" sync of ~/drop to finish
  # uploading. fox-red ignores these deletions (ignoreDelete).
  systemd.user.services.drop-clean = {
    Unit.Description = "Empty ~/drop of what fox-red already has";
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "drop-clean" ''
        set -eu
        PATH=${lib.makeBinPath (with pkgs; [ curl jq gnugrep findutils ])}
        drop=${config.home.homeDirectory}/drop
        key=$(grep -oP '(?<=<apikey>)[^<]+' ${config.xdg.stateHome}/syncthing/config.xml)
        done=$(curl -fsS -H "X-API-Key: $key" \
          "http://127.0.0.1:8384/rest/db/completion?folder=drop&device=${peers.fox-red.id}" | jq .completion)
        [ "$done" = 100 ] || { echo "fox-red has $done% of ~/drop; keeping everything"; exit 0; }
        # ctime: when the file landed here, whatever its original date.
        # (Not -prune: -delete turns it off. .stfolder must survive.)
        find "$drop" -mindepth 1 -type f -cmin +4320 -not -path "$drop/.st*" -print -delete
        find "$drop" -mindepth 2 -type d -empty -delete
      '';
    };
  };
  systemd.user.timers.drop-clean = {
    Timer = { OnCalendar = "daily"; Persistent = true; };
    Install.WantedBy = [ "timers.target" ];
  };
}
