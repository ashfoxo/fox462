# fox-red

The NixOS configuration for **fox-red**, a Hetzner VPS (4 vCPU, 8 GB RAM,
40 GB disk, plus a 1 TB Storage Box for music, podcasts, audiobooks and
video).
The whole server is built from this repo: one flake, shared server modules,
encrypted secrets, and a deploy script. fox-red was rebuilt in place in
autumn 2026.

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
| Audiobookshelf (podcasts, audiobooks) | spoken.emberfox.net | NetBird | NixOS module |
| Jellyfin (movies, TV, YouTube) | jellyfin.emberfox.net | NetBird | NixOS module |
| ytdl-sub (YouTube channels as shows) | — (outbound only) | — | NixOS module |
| Seerr (ask for a movie or show) | request.emberfox.net | NetBird | NixOS module |
| Sonarr (TV) / Radarr (movies) | tv.emberfox.net / movies.emberfox.net | NetBird | NixOS module |
| Prowlarr (torrent trackers) | indexers.emberfox.net | NetBird | NixOS module |
| qBittorrent | — (WebUI from fox-red only, see Requests) | — | NixOS module, in the Mullvad-only `qbt` namespace |
| Gatus | foxred.emberfox.net | NetBird | NixOS module |
| Notesnook sync server | notes.emberfox.net (+ auth., events., files. under notes.) | NetBird | Podman (MongoDB, Silo, three apps) |
| Syncthing (Minecraft instances, `~/sync`) | port 22000; dials fox-grey through fox-green's relay | NetBird | NixOS module |
| SSH | fox-red | anywhere, keys only | — |

The firewall opens TCP 22, 80 and 443, and UDP 51820 for NetBird. On the
NetBird interface only, it also opens TCP 22000 for Syncthing.

## How it fits together

```
                 internet                         NetBird (hosted control plane)
                    │                                        │
     arlofox.net, git., ntfy.            *.emberfox.net → 100.73.156.82
                    │                                        │
                    └──────────────► Caddy ◄─────────────────┘
                                       │   private names only answer
                                       │   100.64.0.0/10 and localhost
          ┌────────────┬───────────────┼──────────────┬──────────────┬──────────────┐
   /var/lib/blog   Forgejo + runner   ntfy      Miniflux, Gatus  Navidrome ↔ AudioMuse  Jellyfin,
     /current         (blog builds)                              (Podman "music" net)   Audiobookshelf
```

The music, audiobooks and video all live on the Storage Box, mounted at
`/mnt/music` over encrypted SMB; only the apps' own state is on the VPS.

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
- **Drop folder.** New media goes into `~/drop/{Music,Audiobooks,Movies,TV}`
  on the laptop. Syncthing brings it to the Storage Box, and `drop-sort`
  (02:00) files it once it has fully arrived (`services/syncthing.nix`):
  music into the library, audiobooks into `spoken`, video into
  `/mnt/music/video`. The drop folder itself sits on the Storage Box, so a
  big movie can't fill the VPS disk. The laptop empties its copy after 3
  days; its Filen app backs `~/drop` up.
- **Video.** Jellyfin serves `/mnt/music/video/{Movies,TV,YouTube}` without
  transcoding: everything is H.265, which the phone and laptop play
  directly, and transcoding would swamp the CPU. Movies and TV arrive
  through the drop folder, DVD rips included (`copper pull` on the laptop
  puts fox-copper's encodes there), or through a request (see Requests). ytdl-sub downloads the last year of a
  few YouTube channels into `YouTube`, one show per channel
  (`services/youtube.nix`; a new channel is one line).
- **Music.** Tagged and named in MusicBrainz Picard on the laptop, then
  dropped: drop-sort puts it straight into the library and Navidrome finds it
  within the hour (its own scan). AudioMuse analyses the
  library and supplies Navidrome's "similar songs" through its plugin.
- **Spoken.** Audiobookshelf downloads podcasts into the Storage Box's
  `spoken` folder and serves audiobooks from it.
- **No Docker.** The few containers run under Podman with fully qualified
  images, no daemon.

## Requests

Ask for a movie or show at request.emberfox.net. Sonarr (TV) or Radarr
(movies) finds it through Prowlarr's trackers and has qBittorrent download
it. When it's done they **hardlink** it into `/mnt/music/video/{TV,Movies}`
and Jellyfin picks it up. A hardlink is the same file under a second name,
so seeding costs no extra space.

```
request. ─► tv. / movies. ─► indexers. (tracker search, from fox-red's own IP)
                  │
                  └─► qBittorrent, in namespace qbt ─► wg-qbt ─► Mullvad (Germany)
                         │
     /mnt/music/torrents/complete ──hardlink──► /mnt/music/video/{TV,Movies}
```

- **Isolation** (`services/torrent.nix`). fox-red has no KVM, so this is
  a network namespace, not a VM. qBittorrent's only way out is a Mullvad
  WireGuard tunnel. If the tunnel goes down, the namespace has no route at
  all (the kill switch). From there qBittorrent can't reach the host, the
  LAN or NetBird. It sees only `/mnt/music/torrents`, not the library.
- **Mullvad server.** A random German one, changed every 6 hours on the
  hour (`fox.server.torrent.mullvad.rotateEveryHours` in `default.nix`), and
  whenever it stops answering. It uses the shared
  `modules/server/mullvad-rotate.nix`, like fox-green's exit node. Its key
  is its own Mullvad device (`mullvad-torrent-key`). There's no inbound
  port: Mullvad stopped offering port forwarding.
- **Seeding** stops at ratio 2 or after 14 days, whichever comes first. Then
  Sonarr or Radarr removes the torrent; the library copy stays.
- **qBittorrent's settings are in Nix**, not its WebUI: the config is
  rewritten at every start. To look at it, use an SSH tunnel:
  `ssh -L 8080:10.201.0.2:8080 fox-red`, then open http://localhost:8080.
- **Quality.** The profile is "HD - 720p/1080p" with Remux turned off, so a
  movie is about 5–15 GB instead of 40.

**Accepted risks.**
- A namespace shares fox-red's kernel, so a qBittorrent exploit plus a
  kernel bug would reach the host. A VM would avoid that, but fox-red can't
  run one.
- Tracker searches and metadata lookups leave from fox-red's own IP; only
  the torrents themselves go through Mullvad.
- Sonarr and Radarr can see all of `/mnt/music` except a short denylist
  (`services/arr.nix`), because hardlinks only work within one mount.

**One-time setup in the web UIs** (it all lives in their databases, which
are backed up):

1. **https://indexers.emberfox.net/**: set a Forms login. Don't choose
   "Disabled for local addresses": through Caddy, every visitor looks
   local. Then add public trackers that pass **Test**. Knaben, YTS and
   LimeTorrents work. Skip anything behind Cloudflare (The Pirate Bay blocks
   Hetzner IPs), anything needing FlareSolverr, and I2P trackers.
2. **https://indexers.emberfox.net/settings/applications**: add Sonarr
   (`http://127.0.0.1:8989`) and Radarr (`http://127.0.0.1:7878`), with
   Prowlarr at `http://127.0.0.1:9696` and each app's API key (its Settings
   → General). Then **Sync App Indexers**.
3. **https://tv.emberfox.net/** and **https://movies.emberfox.net/**, each:
   - a root folder (`/mnt/music/video/TV`, `/mnt/music/video/Movies`) under
     Settings → Media Management;
   - a download client under Settings → Download Clients: qBittorrent,
     host `10.201.0.2`, port `8080`, no username or password;
   - under Settings → Connect, ntfy with the `media` topic and its token.
4. **https://request.emberfox.net/**: sign in with Jellyfin
   (`127.0.0.1:8096`), then add Radarr and Sonarr under Settings → Services
   as Default, with Minimum Availability set to **Released**. Do this
   before the first request: a request made with no service set up is
   never sent, even after one is added. Delete it and request it again.

## Repo layout

fox-red is the flake output `fox-red`; its pieces are shared with any other
server (see [`modules/server/README.md`](../../modules/server/README.md)).

| Path | What it is |
| --- | --- |
| `flake.nix`, `flake.lock` (repo root) | The NixOS release (`nixos-26.05`) and sops-nix, pinned |
| `hosts/fox-red/default.nix` | This host: its name, user, domains, backup bucket, and the list of services it runs |
| `hosts/fox-red/hardware-configuration.nix` | Disks and boot for this VPS |
| `hosts/fox-red/secrets/` | One encrypted file per secret |
| `hosts/fox-red/.sops.yaml` | Which age keys can decrypt `secrets/` |
| `modules/server/` | The shared base: SSH, hardening, Caddy, NetBird, Podman, backups, monitoring |
| `modules/server/services/` | One file per service (Forgejo, blog, Miniflux, ntfy, the music stack, …) |
| `deploy.sh`, `secret.sh` (repo root) | Copy the repo to a server and rebuild there; add or replace a secret |

## Deploying

From the workstation, in a clean checkout:

```bash
git commit -am "…"
./deploy.sh fox-red test      # activate now, but reboot returns to the previous version
./deploy.sh fox-red switch    # activate and make it the boot default
```

`switch` and `boot` refuse to run with uncommitted changes, so whatever the
server boots into is always a commit; `test` and `dry-build` may try
uncommitted work, since a reboot undoes `test`. It copies the repo to `/home/arlo/fox-red` and
builds there, so the workstation needs no special Nix trust. Run it in a real
terminal (not piped), since it asks for the sudo password.

To roll back: `git revert` the change and deploy again, or pick an older
generation from the boot menu.

## Updates

```bash
nix flake update && git commit -qam "flake update" && ./deploy.sh fox-red switch
```

There are no automatic upgrades: a server only changes when `deploy.sh`
runs, so nothing lands that wasn't committed and tried first. To keep
security fixes from being forgotten, the health check alerts once the
deployed nixpkgs is more than 21 days old (`modules/server/monitoring.nix`).

Two things update on their own schedule:

- **Navidrome, AudioMuse and the AudioMuse plugin** update together on
  Sundays (`music-stack-update`), because they have to stay on matching
  versions. The nightly `similar-songs-check` alerts if an update breaks them.
- **A new NixOS release** is a one-line change in `flake.nix`. 26.05 stops
  getting fixes around the end of December 2026: move to `nixos-26.11` after
  it ships on 23 November, and to 27.05 by June 2027. Upgrade fox-green first:
  it has the least on it.

## Secrets

Secrets live in `secrets/`, encrypted with sops for two age keys: the
workstation's (its private half in Bitwarden) and fox-red's, derived from its
SSH host key. At boot, sops-nix decrypts each to `/run/secrets/<name>`.
Each service's file lists the secrets it uses (`fox.server.secretNames`) and
what they hold.

```bash
./secret.sh fox-red <name>                    # asks for a value, typing hidden
some-command | ./secret.sh fox-red <name>     # stores stdin exactly
```

A new secret's name goes into `fox.server.secretNames` in the service that
uses it. If
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
Postgres, Notesnook's MongoDB, and the SQLite files of Navidrome,
ntfy, Forgejo, MollySocket, Jellyfin, Sonarr, Radarr, Prowlarr and Seerr. Also backed up: Forgejo's whole state directory (repos,
`app.ini`), Notesnook's attachments, Jellyfin's users, watch history and
settings, the request apps' settings (so their web UI setup is never redone),
the deployed copy of this repo, and the two
Syncthing folders, the Minecraft instances and `~/sync` (without Syncthing's `.stversions`).

Not backed up: `/var/lib/blog` (rebuilt from git), qBittorrent (its
torrents can be added again, its settings are in Nix), the Podman images,
Jellyfin's artwork and metadata (a library scan fetches them again), and the
media on the Storage Box. The box is storage, not backup: the originals of
what's added are in Filen, uploaded from the laptop.

The bucket key can't delete old versions, so a stolen key can't destroy the
backups. Check with `sudo bash check-backup-key.sh /run/secrets/restic-s3-env bagger-red`
(the script is `scripts/check-backup-key.sh`).

On the 1st of each month, `restic-check-offsite` downloads 5% of the
repository and verifies it. The pre-rebuild history is in the old
`redfox-backup` bucket until spring 2027.

## Alerts

Everything alerts through ntfy:

- **health-check**, every 5 minutes: load, disk over 80%, low memory, failed
  units, services stuck restarting, and the torrent tunnel: no Mullvad
  handshake in 5 minutes, a way out of `qbt` other than Mullvad, or its
  firewall rules missing. Each run also sends a `health` heartbeat
  to fox-green's Gatus, and each successful backup a `backup` heartbeat.
- **Failures** of the backup, the monthly repository check, the blog build,
  the drop sort, the YouTube download, the music stack update and the
  similar-songs check.
- **Media:** Sonarr and Radarr post to the ntfy `media` topic (grabbed,
  imported, failed). A quiet alert means `qbt-mullvad-watch` switched to
  another Mullvad server because the current one stopped answering.
- **A stale deploy:** nixpkgs more than 21 days old (see Updates).
- **Gatus on fox-green** watches the sites from outside and alerts when one
  fails, or when a heartbeat says something is wrong or stops arriving (15
  minutes for health, 26 hours for the backup). That's how fox-red being
  down entirely gets noticed. Those alerts go to an ntfy.sh topic, not to
  fox-red's ntfy.

fox-red's own Gatus (foxred.emberfox.net) shows the same checks but alerts
only for fox-green, in return. Who checks what is in
`modules/server/watch.nix`; see [fox-green's README](../fox-green/README.md).

## Nightly schedule (UTC)

| Time | Job |
| --- | --- |
| 01:00 | Miniflux Postgres dump |
| 01:30–01:50 | restic backup |
| 02:00 | Drop folder sorted into music, audiobooks and video |
| 03:30 | Audiobookshelf Audiobooks scan (set in its web UI) |
| 05:30 | Similar-songs check |
| Sun 06:00 | Navidrome + AudioMuse update |
| Sun 06:30 | Notesnook image update |
| 07:30 | YouTube channels downloaded |
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
- **A unit that boots into its own namespace** must not be ordered after
  `network.target` if a WireGuard interface moved into that namespace
  comes before it. That's a cycle, and systemd breaks it by dropping the
  tunnel at boot (`netns-qbt`, `services/torrent.nix`).
- **systemd's `+` prefix** doesn't skip `TemporaryFileSystem` or `BindPaths`.
  A folder a sandboxed unit binds in has to be made by another unit first
  (`qbt-folders`).
- **The \*arr health page** only rechecks every 6 hours. After fixing what
  it complains about, run **Check Health** under System → Tasks.
- **sops:** check that `.sops.yaml` lists fox-red's key before deploying a
  new secret. Activation fails with "0 successful groups" otherwise.
- **secret.sh adds a newline** to a value typed at its prompt. A raw token
  read straight from its file then carries it along: Caddy sent the Njalla
  token with it and failed with `invalid header field value for
  "Authorization"`. Pipe such tokens in with `printf '%s'`.
- **Syncthing** refuses a folder without its `.stfolder` marker, and a
  folder the system creates first (like `~/sync`, which impermanence makes)
  has none. The laptop and desktop now get the marker at boot, in the
  persistent copy only. The `Failed TLS handshake` lines every minute in its
  log are the two Gatus instances checking port 22000; they're harmless.
- **Notesnook** can keep retrying with a login the server no longer accepts
  (`Invalid reference token` in `podman-identity-server`'s log) after its
  containers restart, and the app shows no error, it just stops syncing.
  **Sync now** on each device clears it; if not, sign out and back in, after
  a backup.
- **Notesnook:** mail (confirmation, email 2FA, password reset) goes out
  through Purelymail's SMTP on port 587; Hetzner blocks outbound 25 and 465.
  The mailbox login is in the `notesnook.env` secret and is also the sender.
  The first account is created with `disableSignups = "false"` in
  `modules/server/services/notesnook.nix`; set it to `"true"` and deploy again
  afterwards. Existing notes don't move between servers: export from the old
  account, sign in to the new instance, import. In the app, Settings → Server
  settings takes the four addresses: `notes.emberfox.net` and
  `auth.`, `events.`, `files.` under `notes.emberfox.net`. Those three need
  their own wildcard certificate (`*.notes.emberfox.net`), so the Njalla token
  must be allowed to create `_acme-challenge.notes.emberfox.net`.
