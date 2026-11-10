# fox-den

One [Nix flake](https://nixos.wiki/wiki/Flakes) that builds all of one
person's NixOS machines: a laptop and the servers it talks to. Disk layout,
desktop, apps, VPN, backups and encrypted secrets are all here, so a fresh
install rebuilds the same machine.

It's published to read and borrow from, not to run as-is. Each machine has
its own README in its host folder. This page is the map.

> **This is my threat model, not a template.** Every choice here trades something away: convenience, recoverability, what's exposed and to whom. The trades fit my life, accounts and risks.
>
> A threat model only works when you can explain why you made each trade-off. Copy a piece without the reasoning and you take on the costs without the protection. That's true of any threat model, not just this one.
>
> Read why each piece is here ([Security decisions](#security-decisions)), check whether that reason applies to you, and keep what you understand.

## Map

```
  fox-amber   laptop  ──┐                 ┌──  fox-red     the services
                        ├──  NetBird  ────┤
  ferret-amber  phone ──┘                 └──  fox-green   watchdog, phone exit nodes
```

| | |
| --- | --- |
| **Reaching the internet** | laptop → Mullvad · phone → fox-green → Mullvad |
| **Public** | only fox-red's blog, Git and ntfy; everything else answers NetBird only |
| **Synced** | `~/sync` between laptop, phone and fox-red (fox-red only ever holds it encrypted) · `~/drop` from the laptop to fox-red |
| **Watched** | fox-red and fox-green each watch the other and alert for it |
| **Backed up** | laptop and fox-red, nightly, encrypted, to Scaleway S3 |

NetBird is the private network between the devices. Each machine's README
has the detail.

## Where things are

| Looking for | Where | Read |
| --- | --- | --- |
| The laptop: disk, impermanence, desktop, sandboxes, backups, Secure Boot | `hosts/fox-amber/`, `modules/`, `home/` | [fox-amber](hosts/fox-amber/README.md) |
| The phone: GrapheneOS, network, carrier, backups (set by hand, not built here) | `hosts/ferret-amber/` | [ferret-amber](hosts/ferret-amber/README.md) |
| The main server and its services | `hosts/fox-red/`, `modules/server/services/` | [fox-red](hosts/fox-red/README.md) |
| The watchdog and the phone's exit nodes | `hosts/fox-green/`, `services/exit-nodes.nix` | [fox-green](hosts/fox-green/README.md) |
| How every server is built; adding a server or a service | `modules/server/` | [server modules](modules/server/README.md) |
| Who monitors whom | `modules/server/watch.nix` | [fox-green § Monitoring](hosts/fox-green/README.md#monitoring) |
| Shared values: colour palette, displays, Syncthing devices | `lib/` | |
| Secrets (encrypted) | `secrets/` (personal), `hosts/<server>/secrets/` | [Secrets](#secrets) |
| Standalone scripts, checked by `nix flake check` | `scripts/`, `*.sh` | |

```
flake.nix          inputs, and one line per machine
hosts/<name>/      one folder per machine: hardware, what's unique to it, its README
modules/           NixOS modules
  personal.nix       the bundle every laptop/desktop imports
  common/            what personal machines and servers share (sysctls, Nix, NetBird)
  core/ desktop/ hardware/ network/ services/   the personal machines' pieces
  server/            the servers' pieces (own README)
home/              Home Manager: the desktop and its apps
lib/               shared values
```

## Security decisions

These are the owner's decisions and reasons, not recommendations. Your
threat model may call for less, more, or something different.

The model: a laptop that's lost, stolen or seized; someone with physical
access to it while it's running or switched off; and attackers on the
internet going after the servers. No single failure should hand over
everything, and convenience counts. The aim is to make attacks expensive,
not to make daily use painful.

**Personal machines**

| Decision | Why | Where |
| --- | --- | --- |
| Full-disk encryption, unlocked with a YubiKey or a passphrase | A switched-off laptop holds nothing readable | `modules/boot.nix` |
| Secure Boot with the owner's own keys, firmware password set | A tampered kernel or initrd on `/boot` won't boot | `modules/boot.nix` |
| Root and home wiped at every boot; only listed paths persist | Malware, leftovers and stray files don't survive a reboot | `modules/root-wipe.nix`, `impermanence.nix`, `ephemeral-home.nix` |
| Pulling the YubiKey locks, then powers off | Walking away (or being made to) leaves the disk encrypted | `modules/core/yubikey-removal.nix` |
| New USB devices blocked until approved | Stops fake keyboards and similar attacks on a running machine | `modules/core/usbguard.nix` |
| `sudo` asks every time; no SSH server; kernel modules locked after boot | Local root needs the owner each time, and nothing listens | `modules/core/` |
| Browsers and chat apps sandboxed, mostly with homes in RAM | A compromised app sees one folder, and forgets at power-off | `home/desktop/sandboxes.nix` |
| Mullvad for all traffic, MAC address randomised per network | The local network and the sites visited learn little | `modules/network/vpn.nix` |
| Updates are announced, never applied automatically | Nothing builds as root behind the owner's back | `modules/services/auto-update.nix` |

**Servers**

| Decision | Why | Where |
| --- | --- | --- |
| Most services answer only over NetBird; Caddy also checks the source address | Less exposed to the internet | `modules/server/caddy.nix` |
| One wildcard certificate for the private names | Their names stay out of public certificate logs | `modules/server/caddy.nix` |
| SSH by key only, fail2ban, kernel hardening | The usual baseline | `modules/server/base.nix` |
| Each server has its own secrets key | One compromised server can't read the others' secrets | `hosts/<server>/.sops.yaml` |
| Backups encrypted client-side; the backup key can't delete old versions | A stolen key can't read or destroy the backups | `modules/server/backup.nix`, `scripts/check-backup-key.sh` |
| The config is built on the server, not pushed in | The laptop's user never gets Nix's root-equivalent trust | `deploy.sh` |
| Two servers watch each other | A server that dies outright still gets noticed | `modules/server/watch.nix` |

**Accepted trade-offs.** Some conveniences are kept on purpose: a few
unlocks need only a touch of the key rather than a PIN, one password
manager is the root of recovery, and some apps (a video-call client, one
plain browser) bypass the VPN. Each was weighed and judged worth it for
daily use.

## Everyday commands

```bash
sudo nixos-rebuild switch --flake .#fox-amber   # rebuild the laptop
./deploy.sh <server> test                       # try a server change (a reboot undoes it)
./deploy.sh <server> switch                     # make it stick (needs a clean commit)
./secret.sh <server> <name>                     # add a server secret
./sops.sh secrets/secrets.yaml                  # edit the personal machines' secrets
nix flake update                                # then rebuild / deploy
nix flake check                                 # shellcheck the scripts, run their tests
```

## Secrets

Encrypted with [sops](https://github.com/getsops/sops), decrypted at boot by
[sops-nix](https://github.com/Mic92/sops-nix). The encrypted files are safe
in a public repo; the private keys are not in it.

- **Personal machines:** `secrets/secrets.yaml`, encrypted to one shared key
  (`.sops.yaml`). Edit with `./sops.sh secrets/secrets.yaml`.
- **Servers:** `hosts/<server>/secrets/`, one file per secret, each server
  with its own `.sops.yaml`. Add one with `./secret.sh <host> <name>`. A value
  typed at its prompt gets a trailing newline; pipe raw tokens in exactly:
  `printf '%s' "$TOKEN" | ./secret.sh <host> <name>`.

Without the key the system still builds, but activation fails and login
passwords aren't set, so check decryption before rebooting into a new config.

## Using this as a reference

You can't build it as-is: it's tied to one person's accounts and hardware.
Pieces that lift out cleanly: the impermanence setup, the nixpak sandbox
helper, the Hyprland Lua config, the restic module, the server modules and
their services, and the exit nodes.

To adapt the whole thing, change these first:

- The username `arlo` throughout, and the name on the lock screen
  (`home/desktop/lockscreen.nix`).
- The public age keys in `.sops.yaml` and each `hosts/<server>/.sops.yaml`;
  then replace the encrypted files with your own.
- Backup buckets, domains, NetBird addresses (`lib/syncthing.nix`,
  `modules/server/watch.nix`), the Mullvad addresses in
  `hosts/fox-green/default.nix`, and the time zone (`modules/core/default.nix`).
- Each `hardware-configuration.nix`: regenerate with `nixos-generate-config`.
- The disk layout: a LUKS device `cryptroot` holding btrfs subvolumes `@root`,
  `@home`, `@nix` and `@persist`.

Built against NixOS 26.05 and Home Manager `release-26.05`. The desktop needs
a Hyprland with Lua configuration.

## Credits

Built on [NixOS](https://nixos.org), [Home Manager](https://github.com/nix-community/home-manager),
[impermanence](https://github.com/nix-community/impermanence),
[sops-nix](https://github.com/Mic92/sops-nix), [nixpak](https://github.com/nixpak/nixpak),
[lanzaboote](https://github.com/nix-community/lanzaboote)
and [Hyprland](https://hypr.land).

## License

[MIT](LICENSE)
