# MollySocket: Signal push through ntfy. Outbound only.
{ config, pkgs, lib, inputs, srv, ... }:
{
  # molly.env: MollySocket registration (MOLLY_* variables)
  fox.server.secretNames = [ "molly.env" ];

  # Outbound only: the web server stays off, and pushes may only go to this
  # ntfy. The registration secret comes in as MOLLY_* variables, which
  # override the settings below.
  services.mollysocket = {
    enable = true;
    environmentFile = "/run/secrets/molly.env";
    settings = {
      db = "/var/lib/mollysocket/db.sqlite";
      webserver = false;
      allowed_endpoints = [ "https://ntfy.${config.fox.server.privateDomain}" ];
    };
  };

  fox.server.monitoring.watchUnits = [ "mollysocket.service" ];

  fox.server.backup = {
    # DynamicUser again: back up the real path, not the link.
    paths = [ "/var/lib/private/mollysocket" ];
    sqlite = [ "/var/lib/private/mollysocket/db.sqlite" ];
  };
}
