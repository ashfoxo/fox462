# /home/arlo lives in RAM and is empty at every boot. Only the folders listed
# here survive: they are bind-mounted from /persist/home/arlo.
#
# The old home on the @home subvolume is left untouched underneath the tmpfs
# (see the migration below), so rolling back to an earlier boot entry gets the
# old home back. Once the new setup has run fine for a while, wipe it for good:
#   sudo mount -o subvol=@home /dev/mapper/cryptroot /mnt && sudo rm -rf /mnt/arlo && sudo umount /mnt
#
# To keep something new, add it to `directories` and rebuild. To find what
# you are missing, near the end of a session: find ~ -xdev -type f -newermt '-1 day'
{ pkgs, lib, ... }:

let
  # Folders that survive. Anything not listed is gone at power-off.
  directories = [
    # --- Your files ---
    "Documents" "Downloads" "Pictures" "Videos" "Music" "media" "Filen"
    "fox-den"           # this repo's checkout
    "tailnet"           # send / fetch with the phone
    "torrents"          # qBittorrent downloads
    "sandbox_folders"   # the shared folder of each sandboxed app
    ".password-store"   # pass

    # --- Keys ---
    { directory = ".ssh";   mode = "0700"; }
    { directory = ".gnupg"; mode = "0700"; }
    { directory = ".config/Yubico"; mode = "0700"; }   # u2f_keys: sudo and lock screen with the key

    # --- Sandboxed apps that keep state (sandboxes.nix: state = "disk" / "logins") ---
    ".local/share/sandboxes/signal"
    ".local/share/sandboxes/librewolf"
    ".local/share/sandboxes/prismlauncher"   # Minecraft worlds, synced by syncthing.nix
    ".local/share/whisper"                   # voice note speech model (public download)

    # --- Unsandboxed apps: logins and settings ---
    ".mozilla"                               # the clean Firefox
    ".config/Bitwarden"
    ".config/Notesnook"
    ".config/Typora"
    ".config/VSCodium" ".vscode-oss"
    ".config/libreoffice"
    ".config/darktable"
    ".local/share/kdenlive"
    ".config/feishin"
    ".config/fluent-reader"
    ".config/@filen" ".filen-cli"            # Filen login and CLI login
    ".config/Electron"                       # Filen's IndexedDB (and any Electron app with the default name)
    ".local/share/Steam" ".steam"
    ".zoom"
    ".config/chirp"
    ".local/share/direnv"                    # which .envrc files you allowed
    ".config/syncthing" ".local/state/syncthing"
  ];

  files = [ ".gitconfig" ];

  path = d: if builtins.isString d then d else d.directory;
in
{
  fileSystems."/home/arlo" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "size=30%" "mode=0700" "nosuid" "nodev" ];
    neededForBoot = true;   # impermanence wants its target mounted in the initrd
  };

  # The on-disk @home (hardware-configuration.nix) stays mounted underneath, and
  # impermanence wants everything under a persisted user home mounted early.
  fileSystems."/home".neededForBoot = true;

  # tmpfs mounts as root; hand the top folder to arlo before anything uses it.
  systemd.tmpfiles.rules = [ "d /home/arlo 0700 arlo users -" ];

  environment.persistence."/persist".users.arlo = { inherit directories files; };

  # Login starts Hyprland as arlo straight away (modules/desktop/session.nix),
  # so Home Manager has to have written its files into the fresh home first.
  systemd.services.greetd = {
    after = [ "home-manager-arlo.service" ];
    wants = [ "home-manager-arlo.service" ];
  };

  # One-time, harmless to repeat: copy anything from the old on-disk home that
  # is on the list above into /persist, unless it is already there. Runs in the
  # initrd, before the root is mounted, so the first boot with this setup
  # finds your data where it expects it. Never fails the boot.
  boot.initrd.systemd.services.migrate-home = {
    description = "Copy the on-disk home into /persist (first boot only)";
    wantedBy = [ "initrd.target" ];
    after = [ "rollback.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt
      mount -o subvol=/ /dev/mapper/cryptroot /mnt || exit 0
      if [ -d /mnt/@home/arlo ]; then
        mkdir -p /mnt/@persist/home/arlo
        chown --reference=/mnt/@home/arlo /mnt/@persist/home/arlo || true
        cd /mnt/@home/arlo
        for d in ${lib.escapeShellArgs (map path directories ++ files)}; do
          if [ -e "$d" ] && [ ! -e "/mnt/@persist/home/arlo/$d" ]; then
            cp -a --parents "$d" /mnt/@persist/home/arlo/ || true
          fi
        done
      fi
      cd /
      umount /mnt
      exit 0
    '';
  };
}
