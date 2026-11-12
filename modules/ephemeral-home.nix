# /home/arlo lives in RAM and is empty at every boot. Only the folders listed
# here survive: they are bind-mounted from /persist/home/arlo.
#
# To keep something new, add it to `directories` and rebuild. To find what
# you are missing, near the end of a session: find ~ -xdev -type f -newermt '-1 day'
let
  # Folders that survive. Anything not listed is gone at power-off.
  directories = [
    # --- Your files ---
    "Documents" "Downloads" "Pictures" "Videos" "media" "working"
    # Not Music: the library is on fox-red (Navidrome); ~/Music is RAM-only scratch.
    "fox-den"           # this repo's checkout
    "fox-selfcare"
    "sync"              # synced to every device by Syncthing (home/desktop/syncthing.nix)
    "drop"              # new media for fox-red; empties itself (home/desktop/syncthing.nix)
    "copper"            # fox-copper's rips on their way to Filen (home/desktop/copper.nix)
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
    ".local/share/sandboxes/telegram" ".local/share/sandboxes/vesktop"   # their logins only; the rest is in RAM
    ".local/share/sandboxes/webapp-claude" ".local/share/sandboxes/webapp-elk"
    ".local/share/sandboxes/webapp-messages"
    ".local/share/sandboxes/webapp-spotify"
    ".local/share/sandboxes/prismlauncher"   # Minecraft worlds, synced by syncthing.nix
    ".local/share/whisper"                   # voice note speech model (public download)

    # --- Unsandboxed apps: logins and settings ---
    ".mozilla"                               # the clean Firefox
    ".config/Bitwarden"
    ".config/Notesnook"
    ".config/Typora"
    ".config/VSCodium" ".vscode-oss"
    # Claude Code: chats, memory, settings and login. CLAUDE_CONFIG_DIR
    # (lib/session-vars.nix) moves .claude.json in here too. Chat history and
    # the login token are on disk by choice: convenience over a seized-laptop risk.
    ".claude"
    ".config/libreoffice"
    ".config/darktable"
    ".local/share/kdenlive"
    ".config/feishin"
    ".config/MusicBrainz"                    # Picard's settings (naming script, move-to folder)
    ".local/share/health"                    # the map of your activity area (health-map)
    ".config/fluent-reader"
    ".config/@filen" ".filen-cli"            # Filen login and CLI login
    ".config/rclone"                         # the `filen` remote for `push` (home/desktop/push.nix)
    ".config/Electron"                       # Filen's IndexedDB (and any Electron app with the default name)
    ".local/share/Steam" ".steam"
    ".zoom"
    ".config/chirp"
    ".local/share/direnv"                    # which .envrc files you allowed
    ".config/syncthing" ".local/state/syncthing"
    ".config/helix"
    ".local/state/fox-displays"              # the main display picked with Super + Shift + P (lib/displays.nix)
  ];

  files = [ ".gitconfig" ];
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
  systemd.tmpfiles.rules = [
    "d /home/arlo 0700 arlo users -"
    # Mount point for the Filen app's network drive. NOT persisted: a persisted
    # directory is a bind mount, and rclone refuses to mount over something
    # that is already a mount point ("directory already mounted").
    "d /home/arlo/mnt 0755 arlo users -"
    "d /home/arlo/mnt/filen 0755 arlo users -"
    # Syncthing's marker for ~/sync (home/desktop/syncthing.nix). It refuses
    # a folder without one, so that an empty, unmounted folder can't look
    # like "everything was deleted" and wipe the other devices. Made in the
    # persistent copy only, for the same reason: if ~/sync ever fails to
    # mount, the empty folder left behind has no marker and Syncthing stops.
    "d /persist/home/arlo/sync/.stfolder 0755 arlo users -"
    "d /persist/home/arlo/drop/.stfolder 0755 arlo users -"
    "d /persist/home/arlo/drop/Music 0755 arlo users -"
    "d /persist/home/arlo/drop/Audiobooks 0755 arlo users -"
    "d /persist/home/arlo/drop/Movies 0755 arlo users -"
    "d /persist/home/arlo/drop/TV 0755 arlo users -"
    # Files deleted inside a persisted folder go to that folder's own
    # .Trash-1000 on disk, not to ~/.local/share/Trash (RAM). Empty anything
    # trashed more than 7 days ago; systemd-tmpfiles-clean runs this daily
    # and shortly after boot.
    "e /persist/home/arlo/*/.Trash-1000 - - - 7d"
  ];

  environment.persistence."/persist".users.arlo = { inherit directories files; };

  # Login starts Hyprland as arlo straight away (modules/desktop/session.nix),
  # so Home Manager has to have written its files into the fresh home first.
  systemd.services.greetd = {
    after = [ "home-manager-arlo.service" ];
    wants = [ "home-manager-arlo.service" ];
  };
}
