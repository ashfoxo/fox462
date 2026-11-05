# What every server gets, whatever it runs: the hardened base, secrets, NetBird,
# Caddy, Podman, backups and monitoring. A host imports this, then the
# services it wants from ./services. (The laptop and desktop use
# modules/personal.nix instead.)
{ inputs, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ../common
    ./options.nix
    ./helpers.nix
    ./secrets.nix
    ./base.nix
    ./netbird.nix
    ./podman.nix
    ./caddy.nix
    ./backup.nix
    ./monitoring.nix
    ./alerts.nix
    ./packages.nix
  ];
}
