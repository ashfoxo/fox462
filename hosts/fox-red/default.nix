# fox-red: the Hetzner VPS. It uses the shared server modules, has its own
# sops keys (.sops.yaml here), and is deployed from the laptop with
# ./deploy.sh fox-red. What it runs is the list of services below.
#
# All timers are UTC (local is EST/EDT: subtract 5 or 4). The nightly order
# is in README.md, "Nightly schedule".
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/server

    ../../modules/server/services/blog.nix
    ../../modules/server/services/forgejo.nix
    ../../modules/server/services/gatus.nix
    ../../modules/server/services/miniflux.nix
    ../../modules/server/services/mollysocket.nix
    ../../modules/server/services/music.nix
    ../../modules/server/services/music-ingest.nix
    ../../modules/server/services/notesnook.nix
    ../../modules/server/services/ntfy.nix
    ../../modules/server/services/syncthing.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # The values that make this server this server. Everything else comes from
  # modules/server and the services imported above.
  fox.server = {
    domain = "arlofox.net";               # blog, Git
    privateDomain = "emberfox.net";       # NetBird-only sites
    backup.repository = "s3:https://s3.fr-par.scw.cloud/bagger-red";
  };

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    # Rollback targets from the rescue console, now that reboots are unattended.
    configurationLimit = 20;
  };

  networking.hostName = "fox-red";

  # This server's own Bitwarden key, "fox-red - main" (the rest: server/base.nix).
  users.users.arlo.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOTGiuFvi1cEpBHjp5KXTf4r5ElMoo+YTgqbQx82r2CB"
  ];

  ############################################################################
  # Upgrades
  ############################################################################

  # The release line is pinned in flake.nix now, not by a channel URL here.
  #
  # system.autoUpgrade is deliberately OFF for the rebuild. The old one
  # rebuilt from /etc/nixos/configuration.nix every night at 03:00, which
  # would quietly undo whatever was deployed from this flake that day. Every
  # deploy comes from the workstation instead (deploy.sh), with
  # `nix flake update` first so security fixes keep landing.
  #
  # >>> A pinned release goes EOL silently. Calendar reminder: bump
  # >>> flake.nix to nixos-26.11 by DECEMBER 2026, and to 27.05 by JUNE 2027.

  # NOT the NixOS release. This is the install-time compatibility marker, and
  # it is what pins PostgreSQL's major version under Miniflux. Leave at 24.11.
  system.stateVersion = "24.11";
}
