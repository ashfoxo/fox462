# NetBird runs from nixos-unstable on every machine (see flake.nix); the rest
# stays on stable. Each side configures its own client: network/vpn.nix and
# server/netbird.nix.
{ pkgs, inputs, ... }:
{
  services.netbird.package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.netbird;
}
