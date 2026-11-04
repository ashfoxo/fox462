# Helpers the server modules share, passed to them as the `srv` module
# argument:
#   { pkgs, srv, ... }: ... ${srv.notify} "title" "body" high
#
#   notify              fire-and-forget ntfy alert (never fails its caller)
#   podman              the system podman, for scripts run by systemd
#   secHeaders          Caddy security headers
#   secHeadersDeferCSP  same, but keeps an app's own Content-Security-Policy
#   mkLog / plainLog    Caddy access-log blocks
{ pkgs, ... }:
let
  secHeaders = ''
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
      X-Content-Type-Options "nosniff"
      X-Frame-Options "SAMEORIGIN"
      Content-Security-Policy "frame-ancestors 'self'"
      Referrer-Policy "strict-origin-when-cross-origin"
      -Server
    }
  '';

  # Same block, except the CSP is set only if the backend did not send one.
  # Caddy's `header` REPLACES upstream values, so applying secHeaders above to
  # an app that ships its own Content-Security-Policy silently overwrites it
  # with this frame-ancestors-only policy. The app keeps working, which is why
  # you would never notice, but its real CSP is gone. Forgejo ships its own, so
  # it gets this variant.
  #
  # Miniflux may be losing its own CSP to secHeaders the same way.
  # Not changed here: worth checking separately with curl -I before touching.
  secHeadersDeferCSP = ''
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
      X-Content-Type-Options "nosniff"
      X-Frame-Options "SAMEORIGIN"
      ?Content-Security-Policy "frame-ancestors 'self'"
      Referrer-Policy "strict-origin-when-cross-origin"
      -Server
    }
  '';

  # Caddy access logs, watched by nothing. ntfy and Navidrome both 401
  # legitimate clients holding stale tokens, so no jail could use them.
  mkLog = prefix: keep: host: ''
    log {
      output file /var/log/caddy/${prefix}-${host}.log {
        roll_size 20mb
        roll_keep ${toString keep}
      }
      format json
    }
  '';
  plainLog = mkLog "access" 2;

  # Fire-and-forget ntfy alert. Never fails its caller: an alerting path that
  # can fail a backup or an upgrade is worse than no alerting path.
  # Usage: notify <title> <body> <priority>
  notify = pkgs.writeShellScript "notify" ''
    set -u
    [ -r /run/secrets/ntfy-alert.env ] || exit 0
    . /run/secrets/ntfy-alert.env
    ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 \
      -H "Authorization: Bearer $NTFY_TOKEN" \
      -H "Title: $1" \
      -H "Priority: $3" \
      -d "$2" \
      "$NTFY_URL" >/dev/null 2>&1 || true
    exit 0
  '';

  # The system's own podman, wrapped with NixOS's container config. Scripts
  # run by systemd have no podman on PATH, so they call it by this path.
  podman = "/run/current-system/sw/bin/podman";
in
{
  _module.args.srv = {
    inherit secHeaders secHeadersDeferCSP mkLog plainLog notify podman;
  };
}
