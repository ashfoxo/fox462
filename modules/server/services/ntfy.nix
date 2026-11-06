# ntfy: push notifications, and the channel every alert on the server uses.
# Public (ntfy.<privateDomain>, on an ordinary certificate) so phones can
# reach it from anywhere; the private wildcard stays NetBird-only.
{ config, srv, ... }:
let
  inherit (srv) secHeaders plainLog;
  priv = config.fox.server.privateDomain;
in
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":8090";
      base-url = "https://ntfy.${priv}";
      auth-file = "/var/lib/ntfy-sh/auth.db";
      # UnifiedPush needs anonymous writes to up* topics, granted out of band
      # with: ntfy access '*' 'up*' write-only
      # The alerting topic in ntfy-alert.env must NOT match up*, and needs its
      # own token: ntfy token add arlo
      auth-default-access = "deny-all";
    };
  };

  services.caddy.virtualHosts."ntfy.${priv}".extraConfig = ''
    ${secHeaders}
    ${plainLog "ntfy.${priv}"}
    reverse_proxy 127.0.0.1:8090
  '';

  fox.server.backup = {
    # NOT /var/lib/ntfy-sh. The ntfy module uses DynamicUser, so that path is
    # a symlink to private/ntfy-sh and restic archives the link, not the
    # data. Ownership will not survive a restore either, since the uid is
    # allocated per-boot; systemd re-chowns StateDirectory on start.
    paths = [ "/var/lib/private/ntfy-sh" ];
    sqlite = [ "/var/lib/ntfy-sh/auth.db" ];
  };
}
