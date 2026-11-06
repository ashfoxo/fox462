# Miniflux: RSS reader, private (rss.<privateDomain>).
{ config, ... }:
let
  priv = config.fox.server.privateDomain;
in
{
  # miniflux.env: ADMIN_USERNAME= / ADMIN_PASSWORD=
  fox.server.secretNames = [ "miniflux.env" ];

  services.miniflux = {
    enable = true;
    config = {
      LISTEN_ADDR = "localhost:8080";
      BASE_URL = "https://rss.${priv}";
      POLLING_FREQUENCY = "15";
    };
    # /run is wiped on reboot, but sops-nix decrypts this again on every boot
    # before services start. File contains ADMIN_USERNAME= and ADMIN_PASSWORD=.
    adminCredentialsFile = "/run/secrets/miniflux.env";
  };

  fox.server.privateSites.rss.upstream = "localhost:8080";

  # Dumped nightly at 01:00, ahead of the 01:30 backup, rather than copied live.
  services.postgresqlBackup = {
    enable = true;
    databases = [ "miniflux" ];
    startAt = "*-*-* 01:00:00";
  };
  fox.server.backup.paths = [ "/var/backup/postgresql" ];
}
