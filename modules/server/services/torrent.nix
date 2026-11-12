# Torrents, isolated from the rest of the server. qBittorrent (step 2) runs in
# the network namespace "qbt", whose only way out is a Mullvad WireGuard
# tunnel. fox-red has no KVM, so this is a namespace, not a VM. The tunnel
# moves to a random German Mullvad server every rotateEveryHours, on the
# hour, and when the current one stops answering (../mullvad-rotate.nix).
#
#   host ── veth-qbt 10.201.0.1 ─┬─ 10.201.0.2 veth0 ──┐  namespace qbt
#     │      (WebUI only, see    │                    ├─ wg-qbt ─► Mullvad
#     │       firewall below)    │                    │  (the only route out)
#     └─ eth0 ◄── wg-qbt's encrypted UDP: the tunnel's socket stays on the host
#
# Kill switch: wg-qbt is created on the host and moved into qbt, and its
# default routes (added by qbt-mullvad-rotate) are the namespace's only ones.
# If the tunnel stops, its routes go with it and qbt has no way out at all.
# No rule has to be right for that.
#
# From qbt the host answers nothing it didn't ask for: the firewall below
# drops new connections from veth-qbt (22/80/443 are open on every interface
# otherwise) and anything qbt would have the host forward.
{ config, lib, pkgs, srv, ... }:
let
  ns = "qbt";
  hostEnd = "10.201.0.1";
  nsEnd = "10.201.0.2";
  ip = "${pkgs.iproute2}/bin/ip";
  iptables = "${pkgs.iptables}/bin/iptables";
  m = config.fox.server.torrent.mullvad;
  mullvadRotate = import ../mullvad-rotate.nix { inherit config lib pkgs srv; };
in
{
  options.fox.server.torrent.mullvad = {
    addresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "10.68.12.34/32" "fc00:bbbb:bbbb:bb01::5:c21f/128" ];
      description = "The Address line of the Mullvad WireGuard config made for this key (IPv4 and IPv6).";
    };
    rotateEveryHours = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Move to another German Mullvad server every this many hours, on the hour. Must divide 24.";
    };
  };

  config = lib.mkMerge [ {
    # mullvad-torrent-key: the PrivateKey from the Mullvad config, alone. Its
    # own Mullvad device, separate from fox-green's exit key.
    fox.server.secretNames = [ "mullvad-torrent-key" ];

    systemd.services.netns-qbt = {
      description = "Network namespace for qBittorrent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # No default route here: wg-qbt brings the only one.
      script = ''
        set -eu
        [ -e /run/netns/${ns} ] || ${ip} netns add ${ns}
        ${ip} link show veth-${ns} >/dev/null 2>&1 \
          || ${ip} link add veth-${ns} type veth peer name veth0 netns ${ns}
        # No IPv6 on the veth: no link-local path between qbt and the host.
        ${pkgs.procps}/bin/sysctl -q -w net.ipv6.conf.veth-${ns}.disable_ipv6=1
        ${ip} netns exec ${ns} ${pkgs.procps}/bin/sysctl -q -w net.ipv6.conf.veth0.disable_ipv6=1
        ${ip} addr replace ${hostEnd}/30 dev veth-${ns}
        ${ip} link set veth-${ns} up
        ${ip} -n ${ns} link set lo up
        ${ip} -n ${ns} addr replace ${nsEnd}/30 dev veth0
        ${ip} -n ${ns} link set veth0 up
      '';
    };

    networking.wireguard.interfaces.wg-qbt = {
      ips = m.addresses;
      privateKeyFile = "/run/secrets/mullvad-torrent-key";
      interfaceNamespace = ns;
      # No peer here: qbt-mullvad-rotate picks a German server and adds the
      # default routes inside qbt (mullvad-rotate.nix, merged below).
      peers = [ ];
    };
    systemd.services.wireguard-wg-qbt = {
      requires = [ "netns-qbt.service" "qbt-folders.service" ];
      after = [ "netns-qbt.service" ];
    };

    # Mullvad's resolver, reached through the tunnel. For services that join
    # qbt (BindReadOnlyPaths onto /etc/resolv.conf) and `ip netns exec`.
    environment.etc."netns/${ns}/resolv.conf".text = "nameserver 10.64.0.1\n";

    # Own chains, so a firewall reload replaces exactly these rules. Ahead of
    # nixos-fw, which would otherwise let qbt reach SSH and Caddy. The host
    # reaching the WebUI goes out through OUTPUT, so only replies come back
    # in; and the host forwards nothing to or from qbt.
    networking.firewall.extraCommands = ''
      for c in fox-qbt-in fox-qbt-fwd; do
        ${iptables} -N $c 2>/dev/null || ${iptables} -F $c
      done
      ${iptables} -C INPUT -j fox-qbt-in 2>/dev/null || ${iptables} -I INPUT 1 -j fox-qbt-in
      ${iptables} -C FORWARD -j fox-qbt-fwd 2>/dev/null || ${iptables} -I FORWARD 1 -j fox-qbt-fwd
      ${iptables} -A fox-qbt-in -i veth-${ns} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
      ${iptables} -A fox-qbt-in -i veth-${ns} -j DROP
      ${iptables} -A fox-qbt-fwd -i veth-${ns} -j DROP
      ${iptables} -A fox-qbt-fwd -o veth-${ns} -j DROP
    '';
    networking.firewall.extraStopCommands = ''
      ${iptables} -D INPUT -j fox-qbt-in 2>/dev/null || true
      ${iptables} -D FORWARD -j fox-qbt-fwd 2>/dev/null || true
      for c in fox-qbt-in fox-qbt-fwd; do
        ${iptables} -F $c 2>/dev/null || true
        ${iptables} -X $c 2>/dev/null || true
      done
    '';

    ##########################################################################
    # qBittorrent, inside qbt
    ##########################################################################

    # Torrents live on the Storage Box next to the library, so Sonarr and
    # Radarr hardlink into /mnt/music/video instead of copying: seeding costs
    # no space. Same mount, so the hardlinks work (tested on the share).
    #
    # The WebUI answers only on qbt's end of the veth, without a login from
    # the host (Sonarr, Radarr, your SSH tunnel), and from nowhere else:
    #   ssh -L 8080:${nsEnd}:8080 fox-red   then   http://localhost:8080
    #
    # qBittorrent.conf is rewritten from serverConfig at every start, so a
    # setting changed in the WebUI is lost on restart: change it here.
    # Categories and torrents are kept (their own files in the profile).
    services.qbittorrent = {
      enable = true;
      group = "navidrome";   # the share is navidrome-group-writable (music.nix)
      serverConfig = {
        LegalNotice.Accepted = true;
        BitTorrent.Session = {
          # Torrent traffic only on the tunnel, never on the veth.
          Interface = "wg-qbt";
          InterfaceName = "wg-qbt";
          # The default (memory-mapped files) stalls and balloons on a
          # network share.
          DiskIOType = "Posix";
          DefaultSavePath = "/mnt/music/torrents/complete";
          TempPath = "/mnt/music/torrents/incomplete";
          TempPathEnabled = true;
        };
        Preferences.WebUI = {
          Address = nsEnd;
          AuthSubnetWhitelistEnabled = true;
          AuthSubnetWhitelist = "${hostEnd}/32";
        };
      };
    };

    # The torrents folder must exist before qBittorrent binds it into its
    # sandbox, and can't be made from inside that sandbox.
    systemd.services.qbt-folders = {
      description = "Create qBittorrent's folder on the Storage Box";
      unitConfig.RequiresMountsFor = "/mnt/music";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/mkdir -p /mnt/music/torrents";
      };
    };

    systemd.services.qbittorrent = {
      # Only the namespace is required. Without the tunnel qbt has no route
      # out (the kill switch), so qBittorrent stalls and resumes by itself.
      requires = [ "netns-qbt.service" "qbt-folders.service" ];
      wants = [ "wireguard-wg-qbt.service" ];
      after = [ "netns-qbt.service" "wireguard-wg-qbt.service" "qbt-folders.service" ];
      # Without the share it would download into an empty mount point.
      unitConfig = {
        AssertPathIsMountPoint = "/mnt/music";
        RequiresMountsFor = "/mnt/music";
      };
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/${ns}";
        BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
        # Sees only its own folder on the share, not the library; and can
        # write only there and to its profile.
        ProtectSystem = lib.mkForce "strict";
        TemporaryFileSystem = "/mnt:ro";
        BindPaths = [ "/mnt/music/torrents" ];   # made by qbt-folders
        ReadWritePaths = [ config.services.qbittorrent.profileDir ];
        # No swap on fox-red: if it runs away, it restarts, not a database.
        MemoryMax = "1G";
        Restart = "on-failure";
      };
    };
  }
  (mullvadRotate {
    name = "qbt-mullvad";
    iface = "wg-qbt";
    country = "de";
    everyHours = m.rotateEveryHours;
    # Used only if no server list has been fetched yet; refreshed from
    # Mullvad's API through the tunnel on every switch.
    fallbackRelays = lib.concatStringsSep "\n" [
      "de-ber-wg-001 0qSP0VxoIhEhRK+fAHVvmfRdjPs2DmmpOCNLFP/7cGw= 193.32.248.66"
      "de-dus-wg-101 tX1zfo0TPh0pX1ALF9d5S7O1UjMtDWcT4/RXZ6cTJGw= 80.66.197.3"
      "de-fra-wg-001 HQHCrq4J6bSpdW1fI5hR/bvcrYa6HgGgwaa5ZY749ik= 185.213.155.73"
    ];
    # Inside qbt: wg and the routes act on wg-qbt there, and the server list
    # and DNS go through the tunnel.
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/${ns}";
      BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
    };
  })
  ];
}
