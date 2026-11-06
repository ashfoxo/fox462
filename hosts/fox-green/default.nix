# fox-green: the RackNerd VPS in New York (2 vCPU, 2 GB RAM, 35 GB disk).
#
# Two jobs, both independent of fox-red:
#   - watch fox-red (Gatus, alerting through ntfy.sh, since fox-red's own
#     ntfy goes down with it), and be watched by it;
#   - serve the phone's two exit nodes (services/exit-nodes.nix).
#
# Keep it that way: nothing here should need fox-red to work, and nothing on
# fox-red should need this. Its one site, the Gatus dashboard at
# foxgreen.emberfox.net, is NetBird-only, with its own certificate and its
# own DNS record, so it stays up when fox-red is down. No backup: all of it
# is in this repo, so a rebuild from scratch is the restore.
#
# See README.md in this folder for setting it up.
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ../../modules/server

    ../../modules/server/services/gatus.nix
    ../../modules/server/services/exit-nodes.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  fox.server = {
    # Caddy for the NetBird-only dashboard; nothing public, so 80 and 443
    # stay closed to the internet.
    caddy.public = false;
    backup.enable = false;

    # The Address line of a config from Mullvad's WireGuard generator for
    # this server's key (both parts, IPv4 and IPv6). The server itself is
    # picked at random among Mullvad's New York ones, and changes every 4
    # hours or when it stops answering.
    exitNodes.mullvad.addresses = [
      "10.65.204.58/32"     # IPv4, e.g. 10.68.12.34/32
      "fc00:bbbb:bbbb:bb01::2:cc39/128"    # IPv6, e.g. fc00:bbbb:bbbb:bb01::5:c21f/128
    ];
  };

  boot.loader.grub = {
    enable = true;
    configurationLimit = 10;   # the disk is 35 GB
  };

  networking.hostName = "fox-green";

  # This server's own Bitwarden key, "fox-green - main" (the rest: server/base.nix).
  users.users.arlo.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILoCFM8qGVe/CMD2eMsuEQZ8Vghlne9mTGClkDWJaFRo"
  ];

  # Bump flake.nix to nixos-26.11 once it ships (with fox-red, this one
  # first). This line stays: it records the release fox-green was installed
  # with, not the one it runs.
  system.stateVersion = "26.05";
}
