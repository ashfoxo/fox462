{
  description = "fox-den: NixOS for all of Arlo's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Only for packages that should run ahead of the stable release (NetBird
    # today). Nothing else follows it, and the system itself stays on stable.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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

    # Secure Boot for the personal machines (modules/boot.nix). Pinned to a
    # release; bump the tag by hand.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative partitioning: hosts/<name>/disko.nix is the disk layout,
    # and nixos-anywhere uses it to wipe, partition and install in one go.
    disko = {
      url = "github:nix-community/disko";
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
        fox-red     = mkHost "fox-red";       # server (Hetzner VPS)
        fox-green   = mkHost "fox-green";     # server (RackNerd VPS, New York): watches fox-red, exit nodes
        fox-copper  = mkHost "fox-copper";    # server (spare laptop at home, bare metal)
      };

      # nix flake check: shellcheck the standalone scripts and run their tests.
      # shortcut: scripts inside Nix strings (systemd `script =`) aren't checked;
      # move one to scripts/ when it grows enough to need it.
      checks.x86_64-linux.scripts =
        nixpkgs.legacyPackages.x86_64-linux.runCommand "scripts-check"
          { nativeBuildInputs = [ nixpkgs.legacyPackages.x86_64-linux.shellcheck ]; } ''
            cd ${./.}
            shellcheck -S warning *.sh scripts/*.sh
            bash scripts/dvd-classify-test.sh
            touch $out
          '';
    };
}