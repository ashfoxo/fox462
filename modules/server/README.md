# Server modules

What every server in this repo is built from. `modules/personal.nix` does the
same job for the laptop and desktop.

```
modules/server/
  default.nix     imports everything below; a host imports just this
  options.nix     the fox.server.* options (the per-host values)
  helpers.nix     notify (ntfy alert), heartbeat (to the watching Gatus), podman,
                  Caddy header/log blocks, as `srv`
  secrets.nix     fox.server.secretNames -> hosts/<host>/secrets/<name>
  base.nix        firewall, kernel hardening, Nix, SSH, fail2ban, journald
  netbird.nix  podman.nix  caddy.nix  backup.nix  monitoring.nix  packages.nix
  watch.nix       which server's Gatus checks and alerts for which (data, not a module)
  services/       one file per service; a host imports the ones it runs
```

## How a service plugs in

A service file is self-contained. It enables the service, and registers
whatever it needs *with the shared modules* through merging options, so no
central list is ever edited:

| It needs | It sets |
| --- | --- |
| a secret | `fox.server.secretNames = [ "x.env" ];` |
| a NetBird-only site | `fox.server.privateSites.x.upstream = "127.0.0.1:PORT";` (`"a.x"` for a name one level down: it gets its own wildcard certificate) |
| a public site | `services.caddy.virtualHosts."x.${config.fox.server.domain}"` |
| its state backed up | `fox.server.backup.paths` (and `.exclude`) |
| a database snapshotted | `fox.server.backup.sqlite`, or `.prepare` for a dump command |
| restart-loop alerts | `fox.server.monitoring.watchUnits` |
| an SSH account | `fox.server.ssh.allowUsers` |
| an alert on failure | `${notify} "${config.networking.hostName}: thing FAILED" "..." high` |
| a heartbeat the other server expects | `${heartbeat} <name> true` (or `false "why"`), and the name under the host's `heartbeats` in `watch.nix` |
| an extra health check | `fox.server.monitoring.extraChecks` (append to `problems`) |

Values that differ per host (`fox.server.domain`, `.privateDomain`,
`.backup.repository`, `.ssh.allowUsers`) are set in the host's
`default.nix`. A server with no sites sets `fox.server.caddy.enable = false`
(which also closes 80 and 443); one whose sites are all NetBird-only sets
`fox.server.caddy.public = false` (443 on the NetBird interface only); and
one with nothing worth backing up sets `fox.server.backup.enable = false`.
fox-green does the last two. A service can be imported by any number of
hosts; each host gets its own secrets (`hosts/<host>/secrets/`) and its own
backup bucket.

`*.emberfox.net` points at fox-red, so a NetBird-only site on any other server
needs an A record of its own pointing at that server's NetBird address, and
that server needs its own Njalla token for the certificate. Every server has
one such site: its Gatus dashboard, named after it without the dash
(`foxgreen.emberfox.net`).

## Adding a server

1. `hosts/<name>/default.nix`: import `../../modules/server`, the services it
   should run (including `services/gatus.nix`), and its
   `hardware-configuration.nix`; set `networking.hostName`,
   `system.stateVersion`, its user, and `fox.server.*`. Add it to `watch.nix`
   with the server that watches it.
2. `hosts/<name>/.sops.yaml`: copy fox-red's, with the new server's age key
   (`ssh-to-age` on its host key) and your workstation's.
3. `./secret.sh <name> <secret>` for each name in its `fox.server.secretNames`.
   Pipe raw tokens in with `printf '%s'`: typed at the prompt, a value gets a
   trailing newline.
4. One line in `flake.nix`.
5. `./deploy.sh <name> test`, then `switch`. The very first deploy runs as
   root, before its user exists (see fox-green's README).

## Adding a service

Copy a small one (`services/ntfy.nix` shows a public site, `miniflux.nix` a
private one with a database) and fill in the table above.
