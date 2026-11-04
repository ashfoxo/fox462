# Podman, the only container runtime on a server.
{ config, pkgs, lib, inputs, srv, ... }:
let
  inherit (srv) podman;
in
{
  # Podman, run as root by systemd, with no daemon. Docker is gone: a root
  # daemon listening for commands was one more thing that could be abused.
  #
  # What runs in a container: Navidrome and AudioMuse (its web app, worker
  # and database), from upstream images, so they move in lockstep.
  #
  # Images are fully qualified (docker.io/...): Podman refuses to guess a
  # registry for a short name when nobody is there to answer its prompt.
  #
  # Containers still run as uid 0 internally. no-new-privileges blocks
  # escalation within a container, but a runtime escape lands at host root.
  # Rootless would fix that and is deliberately NOT used: it would break the
  # uid=navidrome mapping on the CIFS mount above. Accepted risk.
  virtualisation.podman = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };

  virtualisation.oci-containers.backend = "podman";
}
