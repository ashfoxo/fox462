# fox-copper

A spare laptop at home: the first bare-metal server, and the test
bed for disaster recovery. Its one job is DVDs: insert one and it rips to
`/var/lib/media`, then encodes whatever is in `{TV,Movies}/Originals` there to
H.265 nightly (`modules/server/services/dvd-rip.nix`). It has no Filen login:
`copper pull` on the laptop brings finished rips over (`home/desktop/copper.nix`).

## Ripping a disc

Insert it. MakeMKV rips it losslessly, `scripts/dvd-classify.sh` sorts it
by its title lengths, and the drive ejects when it's done:

| The disc looks like | It goes to |
| --- | --- |
| a movie | `Movies/Originals/<Title (Year)>/`, the main feature only |
| a TV season | `Unsorted/TV/<label>-<date>/`, episodes only |
| anything else | `Unsorted/<label>-<date>/`, every title of 10+ minutes |

Movies are named from the disc label and TMDB ("INTERSTELLAR" becomes
"Interstellar (2014)"), or the label alone if TMDB has no exact match. If
Jellyfin matches one wrong, fix it with Identify in Jellyfin; don't rename.

`Unsorted` is yours to name and move into `{Movies,TV}/Originals`, since a
disc can't say which season or episode it is: `ssh fox-copper`, then `mv`
in `/var/lib/media` (group `users`, no sudo needed).

Each night at 02:00, `media-encode` encodes what's in `Originals` to H.265
in `Converted`. On the laptop, `copper pull` fetches finished rips and
`copper done` clears them once they're safe in Filen
(`home/desktop/copper.nix`).

**When MakeMKV stops working** with "This application version is too old":
its betas expire about 60 days after release. It comes from nixos-unstable,
which updates it soonest, so `nix flake update` and deploy.

## Encoding a big backlog on a rented server

The laptop encodes a DVD in well under its running time, but 1080p takes it
hours per episode. For a backlog, rent a Hetzner Cloud server with dedicated
vCPUs (CCX line, Ubuntu), run the same script there, and delete the server
after. Stop the laptop's nightly run meanwhile, or both encode the same files:
`sudo systemctl stop media-encode.timer` (start it again after).

The rented server can't reach fox-copper (NetBird only), so the files go
through the laptop as a stream, without landing on its disk. From the laptop:

```bash
scp scripts/media-encode.sh root@<ip>:
ssh fox-copper 'tar -C /var/lib/media -c Movies/Originals TV/Originals' \
  | ssh root@<ip> 'mkdir -p media && tar -C media -x'
ssh root@<ip>
apt-get update && apt-get install -y ffmpeg tmux rclone
export TERM=xterm-256color   # if your terminal is one the server doesn't know (Ghostty)
tmux new -s encode 'MEDIA=/root/media RCLONE_CONFIG=/dev/null JOBS=2 bash media-encode.sh 2>&1 | tee -a encode.log'
```

It resumes where it stopped if interrupted, so just run it again. When it's
done, from the laptop, send the encodes back and delete the server:

```bash
ssh root@<ip> 'tar -C media -c Movies/Converted TV/Converted' \
  | ssh fox-copper 'tar -C /var/lib/media -x'
```

What's different from the VPSes:

- **It runs from the Fox USB drive** (a 1 TB SanDisk Extreme). The internal
  disk keeps its Windows install, untouched. The firmware boots USB first.
- **Its network is the home Wi-Fi, or a phone's USB tether.** When both are
  up, the tether wins (lower route metric). NetBird is the only way in, so
  deploy and SSH as usual (`fox-copper` in `~/.ssh/config` is its NetBird
  address). If it drops off both, fox-red alerts. Njalla is refused over
  IPv6, so certificate renewals always leave through fox-green-direct's
  IPv4, the only address the Njalla token accepts.
- **The disk is declared**, in `disko.nix`: a 1 GB ESP, the rest LUKS
  (`cryptcopper`) holding btrfs `@root`, `@nix` and `@persist`.
- **The disk is encrypted**, unlocked at the laptop with a YubiKey after
  every reboot. Until then the server is down, after a power cut too.
- **Root is wiped every boot**, as on fox-amber (`modules/root-wipe.nix`).
  `/var/lib` and `/var/log` are kept whole in `/persist`, and so is the SSH
  host key (`/persist/etc/ssh`).
- **arlo's password is a sops secret** (`arlo-password`), not `passwd`: the
  wipe would erase `/etc/shadow`.

## Unlocking after a reboot

Plug a YubiKey into the laptop and touch it when it blinks. No key: type the
disk passphrase (Bitwarden) at the prompt.

## Enrolling a YubiKey for unlock

Once per key, with the key plugged into the laptop. Run over SSH; it asks for
the current passphrase (paste it), then a touch:

```bash
sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-partlabel/copper-root
```

Enroll both YubiKeys, so losing one doesn't leave only the passphrase.
`sudo systemd-cryptenroll /dev/disk/by-partlabel/copper-root` lists the slots.

## Reinstalling

The drive is wiped and installed to while plugged into the workstation,
then moved back to the laptop. `disko.nix` names the drive by id, and its
partlabels and LUKS name (`copper-*`, `cryptcopper`) differ from fox-amber's,
so this can't touch fox-amber's own disk. Everything on the drive is lost;
`/persist` holds the server's state, so back it up first if it matters.

**1. The host key**, from Bitwarden ("fox-copper - host key"). With it, the
secrets in `secrets/` still decrypt and nothing needs re-encrypting:

```bash
k=$(mktemp -d)
install -d -m 755 "$k/persist/etc/ssh"
install -m 600 /dev/null "$k/persist/etc/ssh/ssh_host_ed25519_key"
# paste the key from Bitwarden into that file, then:
ssh-keygen -y -f "$k/persist/etc/ssh/ssh_host_ed25519_key" > "$k/persist/etc/ssh/ssh_host_ed25519_key.pub"
```

Key lost? Make a new one with `ssh-keygen -t ed25519 -N "" -C fox-copper -f
"$k/persist/etc/ssh/ssh_host_ed25519_key"`, put its
`nix shell nixpkgs#ssh-to-age -c ssh-to-age < ...pub` in `.sops.yaml` in
place of the old one, and re-create each secret with `./secret.sh`.

**2. Format and install** (everything committed: the flake only sees what git
tracks):

```bash
read -rsp "disk passphrase: " p; printf %s "$p" > /tmp/disk.key; unset p   # /tmp is RAM here
sudo nix run --inputs-from . disko -- --mode destroy,format,mount --flake .#fox-copper
rm /tmp/disk.key
sudo install -d -m 755 /mnt/persist/etc/ssh
sudo install -m 600 -o root -g root "$k"/persist/etc/ssh/ssh_host_ed25519_key /mnt/persist/etc/ssh/
sudo install -m 644 -o root -g root "$k"/persist/etc/ssh/ssh_host_ed25519_key.pub /mnt/persist/etc/ssh/
sudo nixos-install --root /mnt --flake .#fox-copper --no-root-passwd --no-channel-copy
sudo umount -R /mnt && sudo cryptsetup close cryptcopper
rm -rf "$k"
```

**3. Back in the laptop:** Secure Boot off, USB first in the boot order (F2
at power-on). Unlock with the passphrase, then re-enroll the YubiKeys (the
reinstall wiped them).

If its NetBird address changes, update `copper` in
`modules/server/watch.nix` and `~/.ssh/config`.
