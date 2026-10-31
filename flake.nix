{
  description = "fox-den: NixOS for all of Arlo's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      # Must match the nixpkgs release. master tracks unstable and will not
      # evaluate cleanly against a stable nixpkgs.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Follows added so the lock file doesn't carry a second, older nixpkgs
    # and home-manager just for impermanence.
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Declarative secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixPak wrapper library for sandboxing
    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, ... }:
    let
      # Each machine is hosts/<name>/default.nix. When <name> matches its
      # networking.hostName, a plain `nixos-rebuild switch --flake .` on that
      # machine picks it; fox-amber's doesn't (it goes by workstation on the
      # network), so it rebuilds with `--flake .#fox-amber`.
      mkHost = name: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/${name} ];
      };
    in
    {
      # A new machine: add hosts/<name>/ and one line here.
      nixosConfigurations = {
        fox-amber   = mkHost "fox-amber";     # laptop (hostName: workstation)
        fox-blue    = mkHost "fox-blue";      # desktop, boots from external SSD
        fox-red     = mkHost "fox-red";       # server (Hetzner VPS)
      };
    };
}
