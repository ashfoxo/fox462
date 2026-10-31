# The full personal-machine setup: what the laptop and the desktop have in
# common. A host imports this plus its hardware file and any hardware/
# modules it needs. (The server, fox-red, doesn't use it.)
{ inputs, ... }:
{
  imports = [
    ./options.nix
    ./core
    ./boot.nix
    ./impermanence.nix
    ./ephemeral-home.nix
    ./desktop
    ./network/vpn.nix
    ./network/phone.nix
    ./services/restic.nix

    inputs.impermanence.nixosModules.impermanence
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    ./home-manager.nix
  ];
}
