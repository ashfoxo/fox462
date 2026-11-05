# NetBird client.
{ config, pkgs, lib, inputs, srv, ... }:
{
  # netbird-setup-key: one-time NetBird setup key. Only used for the first
  # enrolment; after that it can expire harmlessly.
  fox.server.secretNames = [ "netbird-setup-key" ];

  # NetBird client, joined to NetBird's hosted control plane. Nothing of
  # NetBird's server side runs here. The client comes from nixos-unstable
  # (common/netbird.nix), the same as on the laptop and desktop.
  #
  # Enrols itself on first start with the one-time setup key, then keeps its
  # identity in /var/lib/netbird, so later starts never need the key again.
  # The service, command and interface are all plain "netbird" / wt0:
  #   netbird status
  # The client listens on UDP 51820 for direct peer connections.
  services.netbird.clients.netbird = {
    port = 51820;
    interface = "wt0";
    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird-setup-key".path;
    };
  };
}
