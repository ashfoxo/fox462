{ pkgs, ... }:
{
  ##### Networking #####
  networking.networkmanager.enable = true;
  # Wi-Fi MAC address randomization per connection (stops physical device tracking across venues)
  networking.networkmanager.wifi.macAddress = "stable-ssid";

  networking.firewall.enable = true;
  # wt0 is not trusted. Peers get only the ports opened per port on wt0:
  # just Syncthing's 22000 (below). Everything else this
  # machine does over NetBird is outbound (send/fetch, Navidrome, Miniflux).
  # To allow more: networking.firewall.interfaces.wt0.allowedTCPPorts.
  networking.firewall.checkReversePath = "loose";

  # Syncthing's sync port, open to NetBird peers only (home/desktop/syncthing.nix).
  # The web UI stays on localhost.
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 22000 ];

  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad;
    enableExcludeWrapper = true;
  };

  # --- NetBird ---
  # Routing is by destination: NetBird peers (*.netbird.cloud / 100.x) go out
  # wt0, everything else goes through Mullvad. Keep any nameserver group in the
  # NetBird dashboard non-primary so only peer names resolve through NetBird.
  services.netbird.clients.wt0 = {
    port = 51820;
    interface = "wt0";
    openFirewall = true;          # UDP 51820, for direct P2P instead of relay
    openInternalFirewall = true;  # NetBird's DNS ports on wt0
    ui.enable = true;

    # Written into /var/lib/netbird-wt0/config.json on start.
    config = {
      # Off so the firewall above decides: peers reach only the wt0 ports
      # opened there (Syncthing). With it on, NetBird drops all inbound.
      BlockInbound = false;
      DisableServerRoutes = true;  # this machine never routes for the mesh
      DisableClientRoutes = true;  # ignore pushed routes / exit nodes; Mullvad stays the only exit
    };
  };

  # NetBird bypass for Mullvad firewall.
  # The UDP 51820 rule only matches real uplinks (not wt0, lo or Mullvad).
  # Don't filter on WireGuard header bytes: NetBird runs STUN on the same
  # port, and dropping it breaks direct P2P.
  systemd.services.mullvad-netbird-rules = {
    description = "Let NetBird traffic bypass Mullvad's firewall";
    after = [ "mullvad-daemon.service" "netbird-wt0.service" ];
    wants = [ "mullvad-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f${pkgs.writeText "mullvad-nb.nft" ''
        table inet mullvad-nb
        delete table inet mullvad-nb
        table inet mullvad-nb {
          chain outgoing {
            type route hook output priority -199; policy accept;
            meta mark 0x0001bd00 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
            oifname "wt0" ct mark set 0x00000f41;
          }
          chain incoming {
            type filter hook input priority -199; policy accept;
            iifname != { "wg0-mullvad", "wt0", "lo" } udp dport 51820 ct mark set 0x00000f41;
            iifname "wt0" ct mark set 0x00000f41;
          }
        }
      ''}";
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet mullvad-nb";
    };
  };
}
