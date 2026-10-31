# fox-red

The NixOS configuration for **fox-red**, a Hetzner VPS (4 vCPU, 8 GB RAM,
40 GB disk, plus a 1 TB Storage Box for music). The whole server is built from
this repo: one flake, one `configuration.nix`, encrypted secrets, and a deploy
script. fox-red was rebuilt in place in autumn 2026.

## What runs here

Most services are private and reachable only over NetBird. The blog and the
services other devices have to reach from anywhere are public.

| Service | Address | Reachable from | Runs as |
| --- | --- | --- | --- |
| Blog (Astro, static) | arlofox.net | anywhere | files served by Caddy |
| Forgejo | git.arlofox.net | anywhere (SSH as `forgejo@`) | NixOS module |
| ntfy | ntfy.emberfox.net | anywhere | NixOS module |
| MollySocket | — (outbound only) | — | NixOS module |
| Miniflux | rss.emberfox.net | NetBird | NixOS module |
| Navidrome | music.emberfox.net | NetBird | Podman |
| AudioMuse-AI | muse.emberfox.net | NetBird | Podman (web, worker, Postgres) |
| Uptime Kuma | status.emberfox.net | NetBird | NixOS module |
| SSH | fox-red | anywhere, keys only | — |

The firewall opens TCP 22, 80 and 443, and UDP 51820 for NetBird.

## How it fits together

```
                 internet                         NetBird (hosted control plane)
                    │                                        │
     arlofox.net, git., ntfy.            *.emberfox.net → 100.73.156.82
                    │                                        │
                    └──────────────► Caddy ◄─────────────────┘
                                       │   private names only answer
                                       │   100.64.0.0/10 and localhost
          ┌────────────┬───────────────┼──────────────┬──────────────┐
   /var/lib/blog   Forgejo + runner   ntfy      Miniflux, Kuma   Navidrome ↔ AudioMuse
     /current         (blog builds)                              (Podman "music" network)
```

- **Private names.** DNS for `*.emberfox.net` points at fox-red's NetBird
  address. Caddy also checks the source address, so a request to a private
  name that arrives on the public IP is dropped. One wildcard certificate,
  issued through Njalla's DNS API, covers every private name and keeps them out
  of public certificate logs.
- **The blog** is a separate Astro repo on this Forgejo. A push to `main`
  makes the Forgejo runner on fox-red build it into
  `/var/lib/blog/releases/<commit>` and switch the `current` symlink to it in
  one step. A failed build leaves the live site alone and sends an ntfy
  alert. Old Ghost links (`/rss/`, `/content/images/…`) redirect.
- **Music.** New music dropped in Filen is pulled nightly, tagged by beets
  into the Storage Box, and picked up by Navidrome (`music-ingest.nix`).
  AudioMuse analyses the library and supplies Navidrome's "similar songs"
  through its plugin.
- **No Docker.** The few containers run under Podman with fully qualified
  images, no daemon.

## Repo layout

| File | What it is |
| --- | --- |
| `flake.nix`, `flake.lock` | The NixOS release (`nixos-26.05`) and sops-nix, pinned |
| `configuration.nix` | The whole server, in commented sections |
| `music-ingest.nix` | Filen → beets → Navidrome pipeline |
| `hardware-configuration.nix` | Disks and boot for this VPS |
| `secrets/` | One encrypted file per secret |
| `.sops.yaml` | Which age keys can decrypt `secrets/` |
| `deploy.sh` | Copy the repo to fox-red and rebuild there |
| `secret.sh` | Add or replace a secret |

## Deploying

From the workstation, in a clean checkout:

```bash
git commit -am "…"
./deploy.sh test      # activate now, but reboot returns to the previous version
./deploy.sh switch    # activate and make it the boot default
```

`deploy.sh` refuses to run with uncommitted changes, so whatever is on the
server is always a commit. It copies the repo to `/home/arlo/fox-red` and
builds there, so the workstation needs no special Nix trust. Run it in a real
terminal (not piped), since it asks for the sudo password.

To roll back: `git revert` the change and deploy again, or pick an older
generation from the boot menu.

## Updates

```bash
nix flake update && git commit -qam "flake update" && ./deploy.sh switch
```

Run weekly until automatic upgrades are back on. Those are the next step:
fox-red will upgrade itself nightly from this repo, with an ntfy alert if a
run fails.

Two things update on their own schedule:

- **Navidrome, AudioMuse and the AudioMuse plugin** update together on
  Sundays (`music-stack-update`), because they have to stay on matching
  versions. The nightly `similar-songs-check` alerts if an update breaks them.
- **A new NixOS release** is a one-line change in `flake.nix`. 26.05 stops
  getting fixes around the end of December 2026: move to `nixos-26.11` after
  it ships on 23 November, and to 27.05 by June 2027.

## Secrets

Secrets live in `secrets/`, encrypted with sops for two age keys: the
workstation's (its private half in Bitwarden) and fox-red's, derived from its
SSH host key. At boot, sops-nix decrypts each to `/run/secrets/<name>`.
The top of `configuration.nix` lists what each secret holds.

```bash
./secret.sh <name>                    # asks for a value, typing hidden
some-command | ./secret.sh <name>     # stores stdin exactly
```

A new secret also goes into `secretNames` in `configuration.nix`. If
fox-red is ever reinstalled, its new host key must be added to `.sops.yaml`
and the secrets re-encrypted (`sops updatekeys`) before the first deploy.

Kept outside this repo, in Bitwarden: the age key, the SSH keys, the restic
password, and `ND_PASSWORDENCRYPTIONKEY` (Navidrome's stored passwords are
useless without it). arlo's login password is not backed up anywhere on the
server; after a bare-metal restore, reset it from the Hetzner console.

## Backups

restic, nightly at 01:30 UTC, to the versioned Scaleway bucket
`bagger-red`, keeping 7 daily, 4 weekly and 6 monthly snapshots. Databases are
dumped first rather than copied live: Miniflux's Postgres, AudioMuse's
Postgres, and the SQLite files of Navidrome, Uptime Kuma, ntfy, Forgejo and
MollySocket. Also backed up: Forgejo's whole state directory (repos,
`app.ini`), beets' state, and the deployed copy of this repo.

Not backed up: `/var/lib/blog` (rebuilt from git) and the Podman images.

On the 1st of each month, `restic-check-offsite` downloads 5% of the
repository and verifies it. The pre-rebuild history is in the old
`redfox-backup` bucket until spring 2027.

## Alerts

Everything alerts through ntfy:

- **health-check**, every 5 minutes: load, disk over 80%, low memory, failed
  units, services stuck restarting. It also pushes to an Uptime Kuma monitor.
- **Failures** of the backup, the monthly repository check, the blog build,
  the music stack update and the similar-songs check.
- **Uptime Kuma** watches the sites themselves.

Uptime Kuma runs on fox-red, so it cannot report fox-red being down. An
outside check (healthchecks.io) is part of the next step.

## Nightly schedule (UTC)

| Time | Job |
| --- | --- |
| 01:00 | Miniflux Postgres dump |
| 01:30–01:50 | restic backup |
| 02:10 | Music ingest |
| 05:30 | Similar-songs check |
| Sun 06:00 | Navidrome + AudioMuse update |
| 1st, 07:00 | Backup repository check |

## Lessons worth keeping

- **Njalla:** a name-specific DNS record overrides the wildcard, and a stray
  `_acme-challenge` record breaks the DNS challenge. The wildcard needs no
  per-service records.
- **NetBird:** a pre-shared key or quantum resistance set on one device stops
  the WireGuard handshake with the others. Symptom: connections time out.
- **The blog runner** runs as a systemd DynamicUser. systemd mounts that
  user's own state folder `noexec`, so builds run in `/var/lib/blog/work`; and
  its sandbox refuses to create setgid folders, so that folder has no setgid
  bit.
- **sops:** check that `.sops.yaml` lists fox-red's key before deploying a
  new secret. Activation fails with "0 successful groups" otherwise.
