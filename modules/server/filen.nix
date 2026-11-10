# The Filen rclone remote, for every unit listed in fox.server.filenUnits.
#
# filen-rclone.env: RCLONE_CONFIG_FILEN_* defining the remote `filen:`.
# PASSWORD and API_KEY are `rclone obscure` output, which is reversible
# encoding, not encryption. Treat as plaintext credentials. Re-export the API
# key via the Filen CLI if you ever change the account password.
{ config, lib, pkgs, ... }:
let
  units = config.fox.server.filenUnits;
in
{
  config = lib.mkIf (units != [ ]) {
    fox.server.secretNames = [ "filen-rclone.env" ];
    systemd.services = lib.genAttrs units (_: {
      serviceConfig.EnvironmentFile = [ "/run/secrets/filen-rclone.env" ];
      environment = {
        # No config file is read or created; the env file defines the remote.
        RCLONE_CONFIG = "/dev/null";
        # Filen is faster with one connection per transfer than with them all
        # multiplexed into one HTTP/2 connection.
        RCLONE_DISABLE_HTTP2 = "true";
      };
      path = [ pkgs.rclone ];
    });
  };
}
