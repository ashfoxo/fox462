# fox.server.monitoring.alertOnFailure (options.nix): for each unit listed,
# an onFailure hook and a notify-<unit>-failed service that pushes to ntfy.
{ config, lib, srv, ... }:
{
  systemd.services = lib.mkMerge (lib.mapAttrsToList (unit: a: {
    ${unit}.onFailure = [ "notify-${unit}-failed.service" ];
    "notify-${unit}-failed" = {
      description = "Push an ntfy alert when ${unit} fails";
      serviceConfig.Type = "oneshot";
      script = ''
        ${srv.notify} "${config.networking.hostName}: ${a.title}" \
          "${unit} failed. journalctl -u ${unit}" ${a.priority}
      '';
    };
  }) config.fox.server.monitoring.alertOnFailure);
}
