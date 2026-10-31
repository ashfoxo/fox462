# fox-den

A single [Nix flake](https://nixos.wiki/wiki/Flakes) that builds three NixOS
machines: a laptop, a desktop PC, and a small cloud server. Everything about
them is in this repo: disk layout, desktop, apps, VPN, backups, and
encrypted secrets. Rebuild from a fresh install and you get the same machine
back.

It's one person's setup, published so you can read it, borrow from it, or
use it as a starting point. It is not a ready-to-run distro. See
[Using this as a reference](#using-this-as-a-reference).

## The machines

| Host | What it is | Config |
| --- | --- | --- |
| `fox-amber` | Laptop (Intel); on the network it goes by `workstation` | `hosts/fox-amber/` |
| `fox-blue` | Desktop PC (Ryzen, NVIDIA) that boots NixOS from a portable SSD and leaves the internal Windows drive alone | `hosts/fox-blue/` |
| `fox-red` | Hetzner VPS running a blog, Git forge, RSS reader, music server and more | `hosts/fox-red/` |

The laptop and desktop share almost everything through `modules/personal.nix`.
A host file only says what's different: its hardware, monitors, backup bucket.
The server is separate and has [its own README](hosts/fox-red/README.md).

## What the laptop and desktop get

**A wiped-every-boot root.** The disk is LUKS-encrypted btrfs with four
subvolumes (`@root`, `@home`, `@nix`, `@persist`). At each boot `@root` is
moved aside and replaced with an empty one, and only what's listed in
`modules/impermanence.nix` survives. Old roots are kept for 7 days in case
you forgot to persist something. Unlocking the disk works with a FIDO2 key
(YubiKey) or a passphrase.

**A keyboard-driven desktop.** [Hyprland](https://hypr.land) (configured in
Lua) with a Quickshell bar and notifications, fuzzel, hyprlock and
hypridle, all coloured from one palette in `lib/palette.nix`, which also
colours Qt apps (through qt6ct) and the PDF viewer. greetd logs straight
into Hyprland at boot and Hyprland locks itself, so the lock screen is the
login. Default apps are keyboard-driven too: yazi for files (a scratchpad
on `Super + E`), zathura, imv and mpv. Press `Super + /` for a cheat sheet
that reads the keybinds straight from the running compositor, so it can't
go out of date.

**A home that forgets.** `/home/arlo` is a tmpfs and is empty at every boot.
Only the folders listed in `modules/ephemeral-home.nix` survive (they live in
`/persist/home/arlo`). Pull the YubiKey and the screen locks; if it isn't
back in 10 seconds the machine powers off. `Super + Ctrl + Shift + Esc`
powers off at once, key or no key.

**Sandboxed apps.** Browsers, chat apps, a torrent client and a Minecraft launcher run
inside [nixpak](https://github.com/nixpak/nixpak) (bubblewrap) sandboxes.
Each app gets its own fake home and a single shared folder. Most homes live
in RAM (`/run/sandbox-ram`, up to a quarter of memory) and are gone at
power-off; Signal's stays on disk and LibreWolf keeps only its logins there
(`state` in `home/desktop/sandboxes.nix`). Web apps like
mail and a music player each get their own sandboxed Chromium window and
profile (`home/desktop/webapps.nix`: add one line to the list and you get a
command, a launcher entry and a workspace rule).

**Network privacy.** Mullvad VPN for everything, with a couple of
deliberate exceptions (Zoom and a plain Firefox use `mullvad-exclude`).
[NetBird](https://netbird.io) connects the machines to each other and to the
server, with inbound connections blocked. Wi-Fi MAC addresses are randomised
per network.

**Hardening.** `sudo` wants a YubiKey touch or password every time, with no
cached session. SSH is key-only. Kernel pointer and `dmesg` leaks are closed
and core dumps are off. User accounts are immutable, and their password
hashes come from encrypted secrets.

**Backups.** Nightly [restic](https://restic.net) to an S3-compatible bucket
(Scaleway), encrypted client-side, with 7 daily, 4 weekly, 6 monthly and 1
yearly snapshots kept. The lock screen shows when the last one succeeded.

**Small tools.**
- `Super + Shift + R` records a voice note and transcribes it offline with
  whisper.cpp. `transcribe FILE` does the same for existing audio.
- `send` and `fetch` copy files to and from a phone over SSH.
- A C toolchain with clangd, sanitizers and friends (`home/desktop/dev.nix`).

## The server

`fox-red` is a single-host NixOS config with its own secrets and its own
deploy script. Public services are behind Caddy with automatic HTTPS;
private ones answer only to the NetBird network. Everything alerts through
ntfy. Services, the nightly schedule, backups and lessons learned are all in
[`hosts/fox-red/README.md`](hosts/fox-red/README.md).

## How it's organised

```
flake.nix              Inputs and the list of machines
hosts/<name>/          One folder per machine: hardware + what's unique to it
modules/               System-level NixOS modules
  personal.nix           The bundle every laptop/desktop imports
  options.nix            The few knobs that differ per machine (fox.*)
  core/                  Nix settings, users, SSH, hardening, USB allowlist, time zone
  desktop/               Login (greetd) and Hyprland session, audio, fonts, system apps
  hardware/              laptop.nix (power, thermals), nvidia.nix
  network/               Mullvad + NetBird, phone file transfer
  services/restic.nix    Backups
  boot.nix, impermanence.nix
home/                  Home Manager config for the user
  desktop/               Hyprland (hypr/*.lua), Quickshell bar, apps, sandboxes, lock screen, theme
lib/                   Shared values: colour palette, session variables
secrets/               sops-encrypted secrets for the laptop and desktop
sops.sh                Wrapper for editing those secrets
```

### Per-machine options

`modules/options.nix` defines a small `fox.*` interface, so a host can say
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

## Everyday use

Rebuild the machine you're sitting at. A plain `--flake .` picks the output
named after the hostname, which works on fox-blue:

```bash
sudo nixos-rebuild switch --flake .
```

fox-amber is a mobile machine, so on the network it deliberately goes by a
generic name (`workstation`) to blend in. Its hostname doesn't match its
flake output, so name it: `sudo nixos-rebuild switch --flake .#fox-amber`.

Rebuild a specific one: `sudo nixos-rebuild switch --flake .#fox-blue`. Use
`boot` instead of `switch` to apply at next boot.

Deploy the server, from a clean git checkout:

```bash
./hosts/fox-red/deploy.sh test     # activate now; a reboot undoes it
./hosts/fox-red/deploy.sh switch   # activate and make it the default
```

Add a machine: create `hosts/<name>/default.nix` (set
`networking.hostName` to the same name, import `modules/personal.nix` and a
generated `hardware-configuration.nix`), then add one line to
`nixosConfigurations` in `flake.nix`.

Update everything: `nix flake update`, then rebuild.

## Secrets

Secrets are encrypted with [sops](https://github.com/getsops/sops) and
decrypted at boot by [sops-nix](https://github.com/Mic92/sops-nix). The
encrypted files are safe to keep in git; the private keys are not in this
repo.

- **Laptop and desktop:** `secrets/`, encrypted to one shared age key
  (listed in `.sops.yaml`). Edit with `./sops.sh secrets/secrets.yaml`.
- **Server:** `hosts/fox-red/secrets/`, one file per secret, with its own
  `.sops.yaml`. Add one with `./hosts/fox-red/secret.sh <name>`.

If you can't decrypt, the system will still build, but activation will fail
and login passwords won't be set. Check that decryption works before you
reboot into a new config.

## Using this as a reference

You can't build this as-is, since it's tied to one person's accounts and
hardware. Most of it is meant to be lifted in pieces. The impermanence
setup, the nixpak sandbox helper, the Hyprland Lua config, the restic
module and the server's service definitions are all fairly self-contained.

If you want to adapt the whole thing, change these first:

- The username `arlo` appears throughout, and the lock screen has a name in
  `home/desktop/lockscreen.nix`.
- `.sops.yaml` and `hosts/fox-red/.sops.yaml` hold the owner's public age
  keys. Put in yours and replace the files in `secrets/` with your own.
- Backup buckets, domain names, NetBird addresses (`modules/network/phone.nix`)
  and the time zone (`modules/core/default.nix`) are the owner's.
- `hardware-configuration.nix` in each host folder is generated for that
  specific machine. Regenerate yours with `nixos-generate-config`.
- Disk layout assumptions: a LUKS device named `cryptroot` containing btrfs
  subvolumes `@root`, `@home`, `@nix` and `@persist`.
- The wallpaper (`home/desktop/wallpapers/`) is just an image; swap it.

Built against NixOS 26.05 and Home Manager `release-26.05`. The desktop
config uses Hyprland's Lua configuration, so it needs a Hyprland version that
supports it.

## Credits

Built on [NixOS](https://nixos.org), [Home Manager](https://github.com/nix-community/home-manager),
[impermanence](https://github.com/nix-community/impermanence),
[sops-nix](https://github.com/Mic92/sops-nix), [nixpak](https://github.com/nixpak/nixpak)
and [Hyprland](https://hypr.land).

## License

[MIT](LICENSE)
