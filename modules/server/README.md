# Server modules

What every server in this repo is built from. `modules/personal.nix` does the
same job for the laptop and desktop.

```
modules/server/
  default.nix     imports everything below; a host imports just this
  options.nix     the fox.server.* options (the per-host values)
  helpers.nix     notify (ntfy alert), podman, Caddy header/log blocks, as `srv`
  secrets.nix     fox.server.secretNames -> hosts/<host>/secrets/<name>
  base.nix        firewall, kernel hardening, Nix, SSH, fail2ban, journald
  netbird.nix  podman.nix  caddy.nix  backup.nix  monitoring.nix  packages.nix
  services/       one file per service; a host imports the ones it runs
```

## How a service plugs in

A service file is self-contained. It enables the service, and registers
whatever it needs *with the shared modules* through merging options, so no
central list is ever edited:

| It needs | It sets |
| --- | --- |
| a secret | `fox.server.secretNames = [ "x.env" ];` |
| a NetBird-only site | `fox.server.privateSites.x.upstream = "127.0.0.1:PORT";` |
| a public site | `services.caddy.virtualHosts."x.${config.fox.server.domain}"` |
| its state backed up | `fox.server.backup.paths` (and `.exclude`) |
| a database snapshotted | `fox.server.backup.sqlite`, or `.prepare` for a dump command |
| restart-loop alerts | `fox.server.monitoring.watchUnits` |
| an SSH account | `fox.server.ssh.allowUsers` |
| an alert on failure | `${notify} "${config.networking.hostName}: thing FAILED" "..." high` |

Values that differ per host (`fox.server.domain`, `.privateDomain`,
`.backup.repository`, `.ssh.allowUsers`) are set in the host's
`default.nix`. A service can be imported by any number of hosts; each host
gets its own secrets (`hosts/<host>/secrets/`) and its own backup bucket.

## Adding a server

1. `hosts/<name>/default.nix`: import `../../modules/server`, the services it
   should run, and its `hardware-configuration.nix`; set
   `networking.hostName`, `system.stateVersion`, its user, and `fox.server.*`.
2. `hosts/<name>/.sops.yaml`: copy fox-red's, with the new server's age key
   (`ssh-to-age` on its host key) and your workstation's.
3. `./secret.sh <name> <secret>` for each name in its `fox.server.secretNames`.
4. One line in `flake.nix`.
5. `./deploy.sh <name> test`, then `switch`.

## Adding a service

Copy a small one (`services/ntfy.nix` shows a public site, `miniflux.nix` a
private one with a database) and fill in the table above.
