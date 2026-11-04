# Uptime Kuma: watches the sites, private (status.<privateDomain>).
{ config, pkgs, lib, inputs, srv, ... }:
{
  # Runs under a systemd-made user, with its data in /var/lib/private/uptime-kuma
  # and /var/lib/uptime-kuma as a link to it.
  #
  # 2.x, where the container was 1.x. The first start upgraded the database,
  # one way; the 1.x copy is in /var/lib/uptime-kuma.v1-backup until cleanup.
  # Listens on 127.0.0.1:3001. Its monitors reach the private sites from the
  # server's own NetBird address, which Caddy lets in.
  #
  # The module removes every privilege, so ping (ICMP) monitors cannot work.
  # Use HTTP or TCP monitors.
  services.uptime-kuma.enable = true;

  fox.server.privateSites.status.upstream = "127.0.0.1:3001";

  fox.server.monitoring.watchUnits = [ "uptime-kuma.service" ];

  fox.server.backup = {
    # DynamicUser: /var/lib/uptime-kuma is a symlink, so back up the real path.
    paths = [ "/var/lib/private/uptime-kuma" ];
    sqlite = [ "/var/lib/private/uptime-kuma/kuma.db" ];
  };
}
