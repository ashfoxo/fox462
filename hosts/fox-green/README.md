# fox-green

The NixOS configuration for **fox-green**, a small RackNerd VPS in New York
(2 vCPU, 2 GB RAM, 35 GB disk). It does two jobs, and is built so that
neither depends on the other server, fox-red:

- **Watching fox-red, and being watched by it.** A server can't report its
  own death, so each one runs Gatus and keeps an eye on the other.
- **Exit nodes for a phone.** Two NetBird peers the phone can send all its
  traffic through: one out through Mullvad, one out from the server's own
  address.

It also runs a small private Syncthing relay, the one way fox-grey (a
Windows PC off NetBird, used for Minecraft) reaches fox-red.

New York, because the phone's carrier appears to run its network on AWS and
hand traffic to the internet around Ashburn, Virginia. That's a best guess
from latency and traceroutes, not something the carrier publishes. If it's
right, a server a few milliseconds from there adds almost nothing to the
phone's latency, wherever the phone is.

## What runs here

| Service | Address | Reachable from |
| --- | --- | --- |
| Gatus | foxgreen.emberfox.net | NetBird |
| Exit node through Mullvad | NetBird peer `fox-green-mullvad` | NetBird |
| Exit node from the server's own IP | NetBird peer `fox-green-direct` | NetBird |
| Syncthing relay (private, token-only) | fox-green:22067 | anywhere |
| SSH | fox-green | anywhere, keys only |

The firewall opens TCP 22 and 22067, and UDP 51820 and 51821 for the two NetBird
peers. On the NetBird interface only, it also opens TCP 443 for the
dashboard.

**The dashboard is served from here, not through fox-red,** so it stays up
when fox-red is down. Caddy runs NetBird-only (`fox.server.caddy.public` is
off): nothing listens publicly, and like fox-red it drops requests that
don't come from a NetBird address. `foxgreen.emberfox.net` has its own DNS
record pointing at this server's NetBird address, which overrides the
`*.emberfox.net` wildcard that points at fox-red. The certificate is the
same kind fox-red uses, a `*.emberfox.net` wildcard from the DNS challenge
through Njalla, with fox-green's own API token.

There's no backup job (`fox.server.backup.enable` is off). Everything about
the server is in this repo, so rebuilding it from scratch is the restore.

## The exit nodes

```
phone ─NetBird─► wt0 ─ rule: from wt0, use table 51 ─► wg-mullvad ─► a Mullvad server in New York
                        table 51 ends in a blackhole: no tunnel, no traffic

phone ─NetBird─► wt1, in its own network namespace ─► veth ─► host ─► the server's own IP
```

**Why two.** Mullvad hides the phone from the network it's on and from the
sites it visits, but some sites, banks especially, block Mullvad's
addresses. The second exit is for those: on an untrusted network, it still
keeps traffic away from whoever runs that network, and gives sites one
stable data-centre address. That address is the same every time and paid for
in one name, so it identifies you to sites more than a carrier's shared
address does; it protects you from the local network, not from the sites.

**Two NetBird clients on one server.** NetBird tells exit nodes apart only by
which peer serves them, so each exit is its own peer, named for how its
traffic leaves: `fox-green-mullvad` and `fox-green-direct`. Those are the
names the phone's NetBird app lists. The Mullvad one is also the server's
own NetBird identity, the one SSH and fox-red's Gatus use. The second client runs
in a network namespace of its own: two NetBird interfaces sharing one
routing table would both claim the NetBird subnet, and replies could go back
to the phone through the wrong peer, which the phone drops.

**Only the phone's traffic goes through Mullvad.** A policy rule sends
traffic arriving from NetBird to its own routing table (51). The server's
own traffic, NetBird, SSH, Gatus and alerts, uses the normal table, so a
Mullvad outage never silences the monitoring.

**Kill switch.** Table 51 holds the tunnel's route and, under it, a
blackhole. If the tunnel goes away, the blackhole is all that's left, and the
phone's traffic is dropped rather than sent out unprotected. The rules and
the blackhole are never removed, not even during a deploy.

**Which Mullvad server.** None is fixed in the config. `mullvad-rotate`
reads Mullvad's own server list and picks a random active one in New York
(`exitNodes.mullvad.city`). It runs when the tunnel comes up and every 4
hours on the hour (`rotateEveryHours`). Every minute, `mullvad-watch` pings through the tunnel;
after two silent minutes it switches to another server and sends a quiet
alert. A WireGuard key works on every Mullvad server, so switching only
changes the peer. Each switch gives the phone a new exit address, so open
connections through this exit drop and reconnect. If Mullvad's list can't be
fetched, the last copy is used, and failing that a few servers built in.

**IPv6.** The server has only an IPv4 address, but the tunnel carries IPv6
too, using the IPv6 address Mullvad gives the key. The phone gets IPv6
through the Mullvad exit when IPv6 is turned on for the NetBird network:
NetBird then pairs every exit node's `0.0.0.0/0` with a `::/0`. The direct exit
has no IPv6 to offer, so it refuses IPv6 at once and the phone falls back to
IPv4 straight away.

**DNS.** Not from these servers: the phone uses Quad9 (`dns.quad9.net`) as
its private DNS, which works through either exit
([ferret-amber](../ferret-amber/README.md)).

All in `modules/server/services/exit-nodes.nix`.

## Monitoring

`modules/server/watch.nix` lists what each server checks and which heartbeats
it expects. Both Gatus instances check everything, so either dashboard shows
the whole picture, but only one side alerts for each server, so a problem
doesn't arrive twice:

| | alerted by | through |
| --- | --- | --- |
| fox-red's sites, and its `health` and `backup` heartbeats | fox-green | a topic on ntfy.sh |
| fox-green's Gatus and SSH, and its `health` heartbeat | fox-red | fox-red's own ntfy |

fox-green's alerts go to ntfy.sh, not to fox-red's ntfy, because they matter
most when fox-red is down.

**Heartbeats.** Every 5 minutes each server's health check sends a heartbeat
to the other server's Gatus, failed if anything is wrong, and fox-red's
nightly backup sends one when it succeeds. Gatus alerts on a failed one, and
on silence: 15 minutes without a health heartbeat, 26 hours without a backup
one. Silence is how a server that's down entirely gets noticed.

**fox-green's health check** covers the exits as well as the usual load,
disk, memory and failed units. It fails if the Mullvad handshake is more than
5 minutes old (by then switching servers hasn't helped), if a routing rule or
the blackhole is missing, or if the direct exit's namespace has no way out.

## Repo layout

| Path | What it is |
| --- | --- |
| `hosts/fox-green/default.nix` | This host: its name, user, Mullvad addresses, and the services it runs |
| `hosts/fox-green/hardware-configuration.nix`, `networking.nix` | Disk, boot and network, from `nixos-generate-config` and the network RackNerd set up |
| `hosts/fox-green/secrets/`, `.sops.yaml` | Its encrypted secrets, and who can decrypt them |
| `modules/server/services/exit-nodes.nix` | Both exit nodes and their health checks |
| `modules/server/mullvad-rotate.nix` | The Mullvad server rotation, shared with fox-red's torrent tunnel |
| `modules/server/services/gatus.nix`, `modules/server/watch.nix` | Gatus, shared with fox-red, and who watches whom |
| `modules/server/services/syncthing-relay.nix` | The private Syncthing relay for fox-grey |

Everything else comes from the shared server modules
([`modules/server/README.md`](../../modules/server/README.md)).

## Secrets

Encrypted with sops for the workstation's age key and fox-green's own (from
its SSH host key). fox-red's key isn't on the list, so neither server can
read the other's secrets.

| Secret | Holds |
| --- | --- |
| `njalla-token` | Njalla API token for the certificate: only `emberfox.net`, only TXT records starting `_acme-challenge`, the four record methods, and only from this server's IP |
| `mullvad-wg-key` | The WireGuard private key registered with Mullvad (its IPv4 and IPv6 addresses go in `default.nix`) |
| `netbird-setup-key`, `netbird-direct-setup-key` | One-time NetBird setup keys, one per peer; unused after enrolment |
| `ntfy-alert.env` | `NTFY_URL` (the ntfy.sh topic) and an empty `NTFY_TOKEN` |
| `gatus.env` | `GATUS_NTFY_URL`, `GATUS_NTFY_TOPIC`, `GATUS_NTFY_TOKEN`, and `HEARTBEAT_TOKEN`, which fox-red sends with its heartbeats |
| `syncthing-relay-token` | The token a device needs to register with the relay (only fox-grey has it) |
| `heartbeat.env` | `HEARTBEAT_URL` (fox-red's Gatus, `https://foxred.emberfox.net`) and `HEARTBEAT_TOKEN` (the one fox-red's Gatus expects) |

## Deploying and updates

The same as fox-red: `./deploy.sh fox-green test`, then `switch`, and
`nix flake update` for updates. When a new NixOS release comes out,
fox-green upgrades first, since it has the least on it.

## Checking on it

```bash
cat /var/lib/mullvad-rotate/current          # the Mullvad server in use
journalctl -u mullvad-rotate -u mullvad-watch -n 20
sudo wg show wg-mullvad                      # its handshake
ip rule show priority 100; ip -6 rule show priority 100
ip route show table 51                       # tunnel route and blackhole
sudo systemctl start mullvad-rotate          # move to another server now
sudo netbird status; sudo netbird-direct status   # the two peers
```

To see the kill switch work: with the phone on the `fox-green-mullvad` exit, run
`sudo ip link set wg-mullvad down`. The phone should lose its connection, not
fall back to the server's own address. `sudo systemctl restart
wireguard-wg-mullvad` brings it back, on a new server.

## If you borrow this

- **Mullvad.** Generate a WireGuard key in your Mullvad account (its config
  generator does this). The key's addresses go in `exitNodes.mullvad.addresses`,
  the private key in the `mullvad-wg-key` secret. Change `country` and `city`
  to wherever your server is.
- **NetBird.** Each peer needs an exit node route with masquerade on, given
  to the phone's group, and turn off login expiry for both peers. For IPv6
  through the exit, turn on IPv6 for the network.
- **Check for leaks** from the phone at https://mullvad.net/check, through
  each exit. The IPv6 line should never show the phone's carrier.
- **The first deploy** has to run as root (the `arlo` account doesn't exist
  yet), and the config turns root logins off. Keep a root session open to set
  the account's password afterwards.
- **The dashboard's name** needs an A record of its own pointing at the
  server's NetBird address, and the server its own Njalla token, restricted
  to its IP (see Secrets).
