# fox-amber

The laptop (Intel, Dell Latitude). On the network it goes by the generic
name `workstation`, so a mobile machine blends into whatever network it
joins. Because that doesn't match its flake output, rebuild it by name:

```bash
sudo nixos-rebuild switch --flake .#fox-amber   # or `boot` to apply at next boot
```

Almost everything here comes from `modules/personal.nix`, the bundle any
personal machine imports. This folder only says what's specific to this
laptop: its hardware, its backup bucket, the update check and `nix-ld`. A
future desktop would import the same bundle and get everything below except
the laptop-only parts, which are marked.

## Disk and boot

**A root wiped every boot.** The disk is LUKS-encrypted btrfs with four
subvolumes (`@root`, `@home`, `@nix`, `@persist`). At each boot `@root` is
moved aside and replaced with an empty one, and only what's listed in
`modules/impermanence.nix` survives. Old roots are kept for a day in case
something should have been persisted (`modules/root-wipe.nix`). The disk
unlocks with a YubiKey (FIDO2) or the passphrase.

**A home that forgets.** `/home/arlo` is a tmpfs, empty at every boot. Only
the folders listed in `modules/ephemeral-home.nix` survive; they live in
`/persist/home/arlo`.

**The YubiKey as a dead man's switch.** Pull it and the screen locks after a
second; if it isn't back within 10 seconds the machine powers off.
`sudo yubikey-away` pauses the power-off (not the lock) until the key is
back. `Super + Ctrl + Shift + Esc` powers off at once, key or no key
(`modules/core/yubikey-removal.nix`).

## Desktop

[Hyprland](https://hypr.land), configured in Lua (`home/desktop/hypr/`), with
a Quickshell bar and notifications, fuzzel, hyprlock and hypridle. Everything
is coloured from one palette, `lib/palette.nix`, which also colours Qt apps
(through qt6ct), the PDF viewer and Jellyfin's web UI. greetd logs straight
into Hyprland and Hyprland locks itself, so the lock screen is the login.

The default apps are keyboard-driven too: yazi for files (a scratchpad on
`Super + E`), zathura, imv and mpv. `Super + /` shows a cheat sheet read
from the running compositor's keybinds, so it can't go out of date.

## Sandboxed apps

Browsers, chat apps, a torrent client and a Minecraft launcher run in
[nixpak](https://github.com/nixpak/nixpak) (bubblewrap) sandboxes. Each gets
its own fake home and a single shared folder. Most homes live in RAM
(`/run/sandbox-ram`, up to a quarter of memory) and are gone at power-off;
Signal's stays on disk, and LibreWolf keeps only its logins there (`state` in
`home/desktop/sandboxes.nix`).

Web apps such as mail and a music player each get their own sandboxed
Chromium window and profile (`home/desktop/webapps.nix`). One line in its
list gives a command, a launcher entry and a workspace rule.

## Network

Mullvad VPN for everything, with deliberate exceptions: Zoom and a plain
Firefox run under `mullvad-exclude`. [NetBird](https://netbird.io) connects
the machines and the servers, with inbound connections blocked except
Syncthing's port. Wi-Fi MAC addresses are randomised per network.

## Hardening

- `sudo` wants the YubiKey PIN and a touch, or the password, every time,
  with no cached session.
- No SSH server, and no text logins on the other consoles.
- New USB devices are blocked until allowed (`modules/core/usbguard.nix`,
  which explains how to allow one).
- Kernel pointer and `dmesg` leaks are closed, core dumps are off, and kernel
  modules can't load once boot is done.
- User accounts are immutable; their password hashes come from encrypted
  secrets.
- The GPG key behind `pass` opens with a YubiKey touch at login.

## Backups

Nightly [restic](https://restic.net) to the Scaleway bucket `bagger-amber`,
encrypted client-side, keeping 7 daily, 4 weekly, 6 monthly and 1 yearly
snapshots (`modules/services/restic.nix`). The bar shows when the last one
succeeded. The bucket key can't delete old versions; check that with
`sudo bash scripts/check-backup-key.sh /run/secrets/rendered/restic-s3-env bagger-amber`.

## Update check (laptop only)

Every 6 hours, as the user and never as root, it checks whether the flake's
inputs have moved and sends a notification if they have. It builds nothing
and leaves the repo alone. It skips metered networks, and the bar shows its
state (`modules/services/auto-update.nix`).

## Small tools

| Command | What it does | Where |
| --- | --- | --- |
| `Super + Shift + R` | Records a voice note and transcribes it offline with whisper.cpp; `transcribe FILE` does an existing file | `home/desktop/voicenotes.nix` |
| `health` | Charts of Gadgetbridge data from `~/sync`, as a page in RAM with no network requests | `home/desktop/health/` |
| `health-map` | Downloads the OpenStreetMap area around your activities for `health` (the one step that goes online, via Mullvad) | `home/desktop/health/` |
| `copper pull` / `copper done` | Fetches fox-copper's DVD rips into `~/copper` (for Filen) and `~/drop` (for Jellyfin), then clears them | `home/desktop/copper.nix` |

Also:

- **`~/sync`** is the same on every device, the phone included, kept in step
  by Syncthing over NetBird, with fox-red holding an always-on copy.
- **`~/drop/{Music,Audiobooks,Movies,TV}`** sends new media to fox-red, which
  files it nightly ([fox-red § How it fits together](../fox-red/README.md#how-it-fits-together)).
- **Filen**'s desktop client runs in the session (`home/desktop/filen.nix`).
- **A C toolchain** with clangd and sanitizers (`home/desktop/dev.nix`).

## Per-machine options

`modules/options.nix` defines a small `fox.*` interface, so a machine can say
what's different without touching shared files:

```nix
fox.backup.repository = "s3:https://s3.fr-par.scw.cloud/my-bucket/my-host";
fox.desktop.monitors = [
  { output = "DP-2"; mode = "3440x1440@59.97"; position = "0x0"; scale = 1; }
  { output = "DP-1"; disabled = true; }
];
fox.desktop.lockAfter = 600;   # seconds idle before the screen locks
```

Other options cover extra Hyprland environment variables, which screen the
bar goes on and the host name in its prompt, and extra GPU device nodes for
the sandboxes.

**Adding another personal machine:** create `hosts/<name>/default.nix` that
imports `modules/personal.nix` and a generated `hardware-configuration.nix`,
and sets `networking.hostName` (the same as `<name>` lets a plain
`--flake .` find it). Then add one line to `nixosConfigurations` in
`flake.nix`.

## Secure Boot

The laptop boots with Secure Boot on, using its own keys instead of
Microsoft's ([lanzaboote](https://github.com/nix-community/lanzaboote),
`modules/boot.nix`). Every boot entry is signed on each rebuild, so a kernel
or initrd swapped on `/boot` won't boot.

One-time setup on a new machine (menu names are a Dell Latitude's):

1. Rebuild. This creates the keys in `/var/lib/sbctl` and signs the boot
   files. `sudo sbctl verify` should list the `.efi` files under
   `/boot/EFI/Linux` and `/boot/EFI/BOOT` as signed.
2. Reboot once with Secure Boot still off, to check it boots.
3. In the firmware (F2 at the logo): set an **Admin Password** (Security),
   then under Secure Boot → Expert Key Management turn on **Custom Mode** and
   **Delete All Keys**. That puts the firmware in Setup Mode.
4. Boot NixOS and run `sudo sbctl enroll-keys --tpm-eventlog`. This enrolls
   only your keys, plus the checksums of the option ROMs this machine
   actually loads. If sbctl refuses because of option ROMs, use
   `--microsoft` instead.
5. Back in the firmware, turn **Secure Boot Enable** on. After booting,
   `bootctl status` shows `Secure Boot: enabled (user)`.

Keep the Admin Password somewhere safe: without it Secure Boot can't be
turned off or re-keyed, and Dell can't reset it on most models.

If it won't boot after an update, pick an older generation in the boot menu
(they're all signed). If nothing boots, enter the firmware with the Admin
Password and turn Secure Boot off.

## Secrets

`secrets/secrets.yaml` at the repo root, encrypted to the shared personal
secrets key, which lives root-only at `/persist/var/lib/sops-nix/secrets_ed25519`.
Edit with `./sops.sh secrets/secrets.yaml`. fox-amber's own Scaleway key is
the `fox-amber-s3-*` entries (`fox.backup.s3SecretPrefix`).
