# Who watches whom, read by services/gatus.nix on every server.
#
# Every server's Gatus checks every server listed here, so each dashboard
# shows the whole picture. Alerts are different: only the server named in
# `watchedBy` alerts for a server. A server can't report its own death, and
# with alerts on one side only, a broken site doesn't ping your phone twice.
#
#   endpoints   Gatus endpoints (https://gatus.io/docs), without group,
#               interval or alerts; gatus.nix adds those.
#   heartbeats  name -> how long the watcher waits before alerting. Each is
#               sent by `srv.heartbeat <name> ...` on the server itself:
#               health from monitoring.nix every 5 min, backup from
#               backup.nix after each nightly run.
let
  # fox-red's NetBird address (DNS for *.emberfox.net points here too).
  red = "100.73.156.82";

  # fox-green's NetBird address, its fox-green-mullvad peer (exit-nodes.nix
  # names it). foxgreen.emberfox.net points here too, by its own DNS record.
  green = "100.73.109.161";

  # Caddy renews 30 days out, so under 10 days left means renewal is failing.
  certOk = "[CERTIFICATE_EXPIRATION] > 240h";
in
{
  fox-red = {
    watchedBy = "fox-green";
    heartbeats = {
      health = "15m";
      backup = "26h";
    };
    endpoints = [
      # Public: checked over the internet, the way visitors reach them.
      { name = "blog"; url = "https://arlofox.net"; conditions = [ "[STATUS] == 200" certOk ]; }
      { name = "git"; url = "https://git.arlofox.net"; conditions = [ "[STATUS] == 200" certOk ]; }
      { name = "ntfy"; url = "https://ntfy.emberfox.net/v1/health"; conditions = [ "[STATUS] == 200" "[BODY].healthy == true" certOk ]; }

      # NetBird-only. These accept anything short of a server error, because
      # some answer a client without a login with a redirect or a 401.
      { name = "rss"; url = "https://rss.emberfox.net/healthcheck"; conditions = [ "[STATUS] == 200" certOk ]; }
      { name = "music"; url = "https://music.emberfox.net/ping"; conditions = [ "[STATUS] < 500" ]; }
      { name = "audiomuse"; url = "https://muse.emberfox.net"; conditions = [ "[STATUS] < 500" ]; }
      { name = "spoken"; url = "https://spoken.emberfox.net/healthcheck"; conditions = [ "[STATUS] == 200" ]; }
      { name = "notes"; url = "https://notes.emberfox.net"; conditions = [ "[STATUS] < 500" ]; }
      { name = "notes-auth"; url = "https://auth.notes.emberfox.net"; conditions = [ "[STATUS] < 500" "[CERTIFICATE_EXPIRATION] > 240h" ]; }
      { name = "status"; url = "https://foxred.emberfox.net/health"; conditions = [ "[STATUS] == 200" ]; }
      { name = "syncthing"; url = "tcp://${red}:22000"; conditions = [ "[CONNECTED] == true" ]; }
      { name = "ssh"; url = "tcp://${red}:22"; interval = "5m"; conditions = [ "[CONNECTED] == true" ]; }
    ];
  };

  fox-green = {
    watchedBy = "fox-red";
    heartbeats = {
      # Includes the exit nodes: fox-green's health check fails when the
      # Mullvad tunnel or the direct exit's namespace is down.
      health = "15m";
    };
    endpoints = [
      { name = "status"; url = "https://foxgreen.emberfox.net/health"; conditions = [ "[STATUS] == 200" certOk ]; }
      { name = "ssh"; url = "tcp://${green}:22"; interval = "5m"; conditions = [ "[CONNECTED] == true" ]; }
    ];
  };
}
