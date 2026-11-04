# Gatus: the status page and uptime alerts, on every server. What it checks
# and which server alerts for which is in ../watch.nix, shared by all of them.
#
# Behind Caddy it's the private site named after the host without its dash:
# foxred.<privateDomain>, foxgreen.<privateDomain>. A server without Caddy
# serves it on port 3001 instead, open on the NetBird interface only.
#
# Its configuration is all here and in watch.nix; the only state is check
# history in /var/lib/private/gatus, which isn't backed up.
{ config, pkgs, lib, inputs, srv, ... }:
let
  host = config.networking.hostName;
  watch = import ../watch.nix;
  behindCaddy = config.fox.server.caddy.enable;
  port = 3001;
  # fox-red -> foxred, so the dashboard is foxred.<privateDomain>.
  site = lib.replaceStrings [ "-" ] [ "" ] host;

  alert = {
    type = "ntfy";
    failure-threshold = 3;
    success-threshold = 2;
    send-on-resolved = true;
  };

  # Every server's endpoints, grouped by server, with alerts only on the
  # servers this one watches.
  endpointsOf = target: map
    (e: { group = target; interval = "1m"; } // e
      // lib.optionalAttrs (watch.${target}.watchedBy == host) { alerts = [ alert ]; })
    watch.${target}.endpoints;

  # Heartbeats from the servers this one watches. One missed or failed
  # heartbeat is enough: they're already minutes apart.
  heartbeatsOf = target: lib.mapAttrsToList
    (name: interval: {
      group = target;
      inherit name;
      token = "\${HEARTBEAT_TOKEN}";
      heartbeat.interval = interval;
      alerts = [ (alert // { failure-threshold = 1; success-threshold = 1; }) ];
    })
    watch.${target}.heartbeats;

  watched = lib.attrNames (lib.filterAttrs (_: t: t.watchedBy == host) watch);
in
{
  # gatus.env (shell-style KEY=value lines, read by systemd; Gatus fills the
  # ${...} below from them):
  #   GATUS_NTFY_URL=    ntfy server for this Gatus's alerts
  #   GATUS_NTFY_TOPIC=  its topic
  #   GATUS_NTFY_TOKEN=  tk_... access token, or empty for an open topic
  #   HEARTBEAT_TOKEN=   what the watched server sends with its heartbeats
  #                      (its heartbeat.env). Letters and digits only:
  #                      openssl rand -hex 32
  fox.server.secretNames = [ "gatus.env" ];

  services.gatus = {
    enable = true;
    environmentFile = "/run/secrets/gatus.env";
    settings = {
      web = {
        address = if behindCaddy then "127.0.0.1" else "0.0.0.0";
        inherit port;
      };
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };
      ui.title = "${host} status";

      # If this server itself loses the internet, Gatus pauses its checks
      # instead of alerting that everything else is down.
      connectivity.checker = {
        target = "1.1.1.1:53";
        interval = "1m";
      };

      alerting.ntfy = {
        url = "\${GATUS_NTFY_URL}";
        topic = "\${GATUS_NTFY_TOPIC}";
        token = "\${GATUS_NTFY_TOKEN}";
        priority = 4;
      };

      endpoints = lib.concatMap endpointsOf (lib.attrNames watch);
      external-endpoints = lib.concatMap heartbeatsOf watched;
    };
  };

  fox.server.privateSites = lib.mkIf behindCaddy {
    ${site}.upstream = "127.0.0.1:${toString port}";
  };
  networking.firewall.interfaces.wt0.allowedTCPPorts = lib.mkIf (!behindCaddy) [ port ];

  fox.server.monitoring.watchUnits = [ "gatus.service" ];
}
