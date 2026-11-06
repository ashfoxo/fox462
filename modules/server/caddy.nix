# Caddy: the web server for every site. It owns the shared setup (certificate
# plugin, the private wildcard); each service adds its own site from its own
# file (fox.server.privateSites for NetBird-only names, or
# services.caddy.virtualHosts for public ones).
{ config, pkgs, lib, srv, ... }:
let
  inherit (srv) secHeaders plainLog;
  priv = config.fox.server.privateDomain;
  sites = config.fox.server.privateSites;

  # A site name may have dots: "rss" is rss.<priv>, "auth.notes" is
  # auth.notes.<priv>. A wildcard certificate covers one label only, so sites
  # are grouped by what follows their first label (their zone) and each zone
  # gets its own wildcard block: "" is *.<priv>, "notes" is *.notes.<priv>.
  zoneOf = name: lib.concatStringsSep "." (builtins.tail (lib.splitString "." name));
  zones = lib.unique ([ "" ] ++ map zoneOf (lib.attrNames sites));

  # One handle block per private site in the zone, in name order. Matcher names
  # can't hold dots.
  handles = zone: lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: site:
      let m = lib.replaceStrings [ "." ] [ "-" ] name; in ''
        @${m} host ${name}.${priv}
        handle @${m} {
          reverse_proxy ${site.upstream}
        }
      '')
    (lib.filterAttrs (name: _: zoneOf name == zone) sites));

  # Every private service (fox.server.privateSites) sits behind a wildcard
  # certificate, one per zone.
  #
  # The certificate comes from the DNS challenge through Njalla, because Let's
  # Encrypt cannot reach a NetBird address. A wildcard also keeps the private
  # names out of the public certificate logs. A site with its own block (ntfy)
  # beats the wildcard, so it stays public on an ordinary certificate.
  #
  # DNS sends *.<priv> to the server's NetBird address, but Caddy still listens
  # on the public IP too, and anyone can send a request there with a private
  # Host header. So the source address is checked as well:
  #   100.64.0.0/10   NetBird peers
  #   127.0.0.0/8 ::1 the server itself
  # Gatus runs on the server, and its requests to these names leave from
  # the server's own NetBird address, so they fall in the first range.
  # Anything else gets its connection dropped with no response, and so do
  # unknown names under the zone.
  privateVhost = zone:
    let
      domain = if zone == "" then priv else "${zone}.${priv}";
      logName = if zone == "" then "private.${priv}" else "private-${zone}.${priv}";
    in
    lib.nameValuePair "*.${domain}" { extraConfig = ''
      tls {
        dns njalla {file./run/secrets/njalla-token}
        propagation_delay 2m
        propagation_timeout 10m
      }
      ${secHeaders}
      ${plainLog logName}

      @outside not remote_ip 100.64.0.0/10 127.0.0.0/8 ::1
      handle @outside {
        abort
      }

      ${handles zone}

      handle {
        abort
      }
    ''; };
in
lib.mkIf config.fox.server.caddy.enable {
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

    virtualHosts = lib.listToAttrs (map privateVhost zones);
  };
}
