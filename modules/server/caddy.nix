# Caddy: the web server for every site. It owns the shared setup (certificate
# plugin, the private wildcard); each service adds its own site from its own
# file (fox.server.privateSites for NetBird-only names, or
# services.caddy.virtualHosts for public ones).
{ config, pkgs, lib, inputs, srv, ... }:
let
  inherit (srv) secHeaders plainLog;
  priv = config.fox.server.privateDomain;
  # One handle block per private site, in name order.
  sites = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: site: ''
    @${name} host ${name}.${priv}
    handle @${name} {
      reverse_proxy ${site.upstream}
    }
  '') config.fox.server.privateSites);
in
{
  # njalla-token: Njalla API token for the wildcard certificate. Limited to the
  # private domain, _acme-challenge TXT records, the four record methods, and
  # the server's own IPv4 and IPv6.
  fox.server.secretNames = [ "njalla-token" ];
  # Caddy reads the Njalla token straight from this file with its {file.*}
  # placeholder (see the wildcard site), so it never lands in the Nix store or
  # the Caddyfile. Owned by caddy because Caddy reads it as itself.
  sops.secrets."njalla-token" = {
    owner = "caddy";
    restartUnits = [ "caddy.service" ];
  };

  systemd.tmpfiles.rules = [ "d /var/log/caddy 0755 caddy caddy -" ];

  services.caddy = {
    enable = true;
    # Only so the ACME CA can warn about renewal failures. Nothing else here
    # would tell you a cert was about to lapse.
    email = "fidgeting.twitch457@anonaddy.com";

    # Stock Caddy plus the Njalla DNS plugin, for the wildcard certificate.
    # The hash pins the plugin's source. On a plugin version bump, set it to
    # lib.fakeHash, build once, and copy the "got:" hash from the error.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/njalla@v1.0.0" ];
      hash = "sha256-FNu+XhEMLr4wWfo+iSoWlxbSurmvPjphU6yTQYd/s3c=";
    };

    virtualHosts = {

      # Every private service (fox.server.privateSites), behind one wildcard
      # certificate.
      #
      # The certificate comes from the DNS challenge through Njalla, because
      # Let's Encrypt cannot reach a NetBird address. A wildcard also keeps
      # the private names out of the public certificate logs. ntfy above has
      # its own site block, which beats this wildcard, so it stays public on
      # an ordinary certificate. Services add their own entry to privateSites.
      #
      # DNS sends *.emberfox.net to fox-red's NetBird address, but Caddy still
      # listens on the public IP too, and anyone can send a request there with
      # a private Host header. So the source address is checked as well:
      #   100.64.0.0/10   NetBird peers
      #   127.0.0.0/8 ::1 fox-red itself
      # Uptime Kuma runs on fox-red, and its requests to these names leave
      # from fox-red's own NetBird address, so they fall in the first range.
      # Anything else gets its connection dropped with no response.
      #
      # Unknown names under the private domain are dropped the same way.
      "*.${priv}".extraConfig = ''
        tls {
          dns njalla {file./run/secrets/njalla-token}
          propagation_delay 2m
          propagation_timeout 10m
        }
        ${secHeaders}
        ${plainLog "private.${priv}"}

        @outside not remote_ip 100.64.0.0/10 127.0.0.0/8 ::1
        handle @outside {
          abort
        }

        ${sites}

        handle {
          abort
        }
      '';

    };
  };
}
