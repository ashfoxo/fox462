# Two NetBird exit nodes on one server, for the phone:
#
#   <host>-mullvad  traffic leaves through Mullvad. If the Mullvad tunnel is
#                   down it is dropped, never sent out unprotected.
#   <host>-direct   traffic leaves from the server's own IP: a stable data
#                   centre address for banking and the like, when the
#                   network you're on can't be trusted but Mullvad's
#                   addresses get blocked.
#
# (On fox-green: fox-green-mullvad and fox-green-direct. Those are the names
# the phone's NetBird app lists as exit nodes.)
#
# NetBird tells exit nodes apart only by which peer serves them, so each is
# its own NetBird client, enrolled as its own peer:
#
#   phone ──NetBird──► wt0 (host) ─ rule: from wt0, use table 51 ─► wg-mullvad ─► Mullvad
#                                        table 51 ends in a blackhole, so no tunnel = no traffic
#
#   phone ──NetBird──► wt1 (namespace "direct") ─► veth ─► host ─► the server's own IP
#
# The direct client lives in its own network namespace because two NetBird
# interfaces on one routing table would both claim the NetBird subnet, and a
# reply could go back to the phone through the wrong peer, which the phone
# drops. In the namespace it has a routing table to itself.
#
# Which Mullvad server: a random active one in the chosen city, from
# Mullvad's own server list. It changes every 4 hours on the hour, every time the tunnel
# starts, and as soon as the current one stops answering (checked every
# minute). Every switch moves the phone to a new exit address, so open
# connections through the Mullvad exit drop and reconnect.
#
# IPv6: the tunnel to Mullvad runs over IPv4 (this server has no IPv6), but
# IPv4 and IPv6 both go through it. The phone gets IPv6 through the Mullvad
# exit once IPv6 is turned on for the NetBird network; NetBird then adds ::/0
# alongside every exit node's 0.0.0.0/0. The direct exit has no IPv6 to give,
# so it refuses IPv6 at once and the phone falls back to IPv4.
{ config, pkgs, lib, srv, ... }:
let
  cfg = config.fox.server.exitNodes;
  ip = "${pkgs.iproute2}/bin/ip";
  iptables = "${pkgs.iptables}/bin/iptables";
  ip6tables = "${pkgs.iptables}/bin/ip6tables";
  grep = "${pkgs.gnugrep}/bin/grep";
  wg = "${pkgs.wireguard-tools}/bin/wg";
  m = cfg.mullvad;

  table = "51";         # Mullvad exit's routing table
  ns = "direct";        # direct exit's network namespace
  hostEnd = "10.200.0.1";
  nsEnd = "10.200.0.2";
  directPort = 51821;   # direct client's WireGuard port, forwarded into the namespace

  # Used only if Mullvad's server list can't be fetched and no copy of it has
  # been saved yet (hostname, public key, address).
  fallbackRelays = lib.concatStringsSep "\n" [
    "us-nyc-wg-001 8kBm0P9xz3cXVn3so1czm5mLv0dEcrM6vFCOlozQ7Hk= 23.165.56.3"
    "us-nyc-wg-002 xtX5Y0+E54jvIvubYLdTwMjCYQlBrmgNaL1tJNQyFlc= 23.165.8.3"
    "us-nyc-wg-003 hC+xgvC/KTutW4crmQx+XEyT5ihy9EIjt7dON4eK0XY= 23.162.8.3"
  ];

  mullvadRotate = import ../mullvad-rotate.nix { inherit config lib pkgs srv; };
in
{
  options.fox.server.exitNodes.mullvad = {
    addresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "10.68.12.34/32" "fc00:bbbb:bbbb:bb01::5:c21f/128" ];
      description = ''
        The IPv4 and IPv6 addresses Mullvad assigned to this server's
        WireGuard key: the Address line of any config Mullvad's WireGuard
        generator makes for it. They are the same on every Mullvad server.
      '';
    };
    country = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "Country code of the Mullvad servers to pick from.";
    };
    city = lib.mkOption {
      type = lib.types.str;
      default = "nyc";
      description = "City code of the Mullvad servers to pick from (nyc, dal, chi, ...).";
    };
    rotateEveryHours = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Move to another Mullvad server every this many hours, on the hour, even when the current one works. Must divide 24.";
    };
  };

  config = lib.mkMerge [ {
    assertions = [{
      assertion = lib.any (a: builtins.match "[0-9.]+/32" a != null) m.addresses
        && lib.any (a: builtins.match "[0-9a-f:]+/128" a != null) m.addresses;
      message = "fox.server.exitNodes.mullvad.addresses needs the IPv4 /32 and the IPv6 /128 Mullvad gave this key (got ${toString m.addresses}).";
    }];

    # mullvad-wg-key:          the PrivateKey from the Mullvad config, alone
    # netbird-direct-setup-key: a second one-time NetBird setup key, for the
    #                          fox-green-direct peer
    fox.server.secretNames = [ "mullvad-wg-key" "netbird-direct-setup-key" ];

    # Forwarding on. NetBird masquerades routed traffic itself; the rules
    # below make sure of it on the two ways out.
    services.netbird.useRoutingFeatures = "server";

    # Replies from Mullvad arrive on wg-mullvad from addresses the main table
    # would send out the public interface, which strict reverse-path
    # filtering drops as spoofed. Loose only asks that a route exists.
    networking.firewall.checkReversePath = "loose";
    boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" = lib.mkForce 2;
    boot.kernel.sysctl."net.ipv4.conf.default.rp_filter" = lib.mkForce 2;

    ##########################################################################
    # Mullvad exit (peer "fox-green", the shared NetBird client on wt0)
    ##########################################################################

    # Exit-node routes from other peers would steer this server's own
    # traffic. It serves exits; it never uses one.
    services.netbird.clients.netbird.config.DisableClientRoutes = true;

    # The peer's name in the dashboard and on the phone, instead of the bare
    # host name. Its NetBird DNS name follows: <host>-mullvad.netbird.cloud.
    services.netbird.clients.netbird.environment.NB_HOSTNAME = "${config.networking.hostName}-mullvad";

    # The interface only: no peer here. mullvad-rotate picks the server and
    # adds the routes, into table 51 only, so the server's own traffic
    # (NetBird, SSH, Gatus, alerts) never depends on Mullvad.
    networking.wireguard.interfaces.wg-mullvad = {
      ips = m.addresses;
      privateKeyFile = "/run/secrets/mullvad-wg-key";
      peers = [ ];
    };

    # The rules and the kill switch, for IPv4 and IPv6. Deliberately never
    # removed on stop: a moment without them during a deploy would send phone
    # traffic out the public interface. Priority 100 is ahead of NetBird's own
    # rules (105+).
    systemd.services.mullvad-exit-routing = {
      description = "Route the Mullvad exit node's traffic into table ${table}, blackholed without the tunnel";
      wantedBy = [ "multi-user.target" ];
      before = [ "netbird.service" "wireguard-wg-mullvad.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for v in -4 -6; do
          ${ip} $v rule show priority 100 | grep -q 'iif wt0 lookup ${table}' \
            || ${ip} $v rule add priority 100 iif wt0 lookup ${table}
          ${ip} $v route replace blackhole default table ${table} metric 4096
        done
      '';
    };

    # Pick a server whenever the tunnel comes up, every rotateEveryHours on
    # the hour, and when it stops answering (mullvad-rotate.nix, merged below).


    ##########################################################################
    # Direct exit (peer "fox-green-direct", a second NetBird client in a netns)
    ##########################################################################

    systemd.services.netns-direct = {
      description = "Network namespace for the direct exit node";
      wantedBy = [ "multi-user.target" ];
      before = [ "netbird-direct.service" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        [ -e /run/netns/${ns} ] || ${ip} netns add ${ns}
        ${ip} link show veth-${ns} >/dev/null 2>&1 \
          || ${ip} link add veth-${ns} type veth peer name veth0 netns ${ns}
        ${ip} addr replace ${hostEnd}/30 dev veth-${ns}
        ${ip} link set veth-${ns} up
        ${ip} -n ${ns} link set lo up
        ${ip} -n ${ns} addr replace ${nsEnd}/30 dev veth0
        ${ip} -n ${ns} link set veth0 up
        ${ip} -n ${ns} route replace default via ${hostEnd}
        ${ip} netns exec ${ns} ${pkgs.procps}/bin/sysctl -q -w net.ipv4.ip_forward=1
        ${ip} netns exec ${ns} ${iptables} -t nat -C POSTROUTING -o veth0 -j MASQUERADE 2>/dev/null \
          || ${ip} netns exec ${ns} ${iptables} -t nat -A POSTROUTING -o veth0 -j MASQUERADE
        # No IPv6 out of this server: refuse it straight away, so the phone
        # falls back to IPv4 instead of waiting for a timeout. Last, and not
        # fatal, so a kernel without IPv6 still gets a working IPv4 exit.
        ${ip} -6 -n ${ns} route replace unreachable default \
          || echo "no IPv6 here; IPv6 from the phone gets no answer" >&2
      '';
    };

    # The namespace gets its own resolv.conf: the host's may point at the
    # other NetBird client's resolver, which this namespace can't reach.
    environment.etc."netns/${ns}/resolv.conf".text = ''
      nameserver 9.9.9.9
      nameserver 149.112.112.112
    '';

    services.netbird.clients.direct = {
      # The peer's name in the dashboard and on the phone.
      environment.NB_HOSTNAME = "${config.networking.hostName}-direct";
      port = directPort;
      interface = "wt1";
      # Its port is reached through the forward below, not the host firewall.
      openFirewall = false;
      openInternalFirewall = false;
      login = {
        enable = true;
        setupKeyFile = config.sops.secrets."netbird-direct-setup-key".path;
      };
      config = {
        DisableClientRoutes = true;
        # DNS for this peer would be set up inside the namespace, where
        # nothing uses it. The phone's DNS doesn't come from here.
        DisableDNS = true;
      };
    };

    systemd.services.netbird-direct = {
      requires = [ "netns-direct.service" ];
      after = [ "netns-direct.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/${ns}";
        BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
      };
    };

    ##########################################################################
    # NAT on the host
    ##########################################################################

    # Own chains, so a firewall reload replaces exactly these rules.
    #   - Anything leaving through Mullvad takes the tunnel's address
    #     (Mullvad drops any other source).
    #   - The namespace's traffic takes the server's public address.
    #   - The direct client's WireGuard port is forwarded in, so peers can
    #     reach it directly instead of through a relay. LOCAL only: phone
    #     traffic heading elsewhere to that port must not be caught.
    networking.firewall.extraCommands = ''
      ${ip6tables} -t nat -N fox-exit-post 2>/dev/null || ${ip6tables} -t nat -F fox-exit-post
      ${ip6tables} -t nat -C POSTROUTING -j fox-exit-post 2>/dev/null \
        || ${ip6tables} -t nat -A POSTROUTING -j fox-exit-post
      ${ip6tables} -t nat -A fox-exit-post -o wg-mullvad -j MASQUERADE

      for c in fox-exit-post fox-exit-pre; do
        ${iptables} -t nat -N $c 2>/dev/null || ${iptables} -t nat -F $c
      done
      ${iptables} -t nat -C POSTROUTING -j fox-exit-post 2>/dev/null \
        || ${iptables} -t nat -A POSTROUTING -j fox-exit-post
      ${iptables} -t nat -C PREROUTING -j fox-exit-pre 2>/dev/null \
        || ${iptables} -t nat -A PREROUTING -j fox-exit-pre
      ${iptables} -t nat -A fox-exit-post -o wg-mullvad -j MASQUERADE
      ${iptables} -t nat -A fox-exit-post -s ${nsEnd}/32 ! -o veth-${ns} -j MASQUERADE
      ${iptables} -t nat -A fox-exit-pre ! -i veth-${ns} -m addrtype --dst-type LOCAL \
        -p udp --dport ${toString directPort} -j DNAT --to-destination ${nsEnd}:${toString directPort}
    '';
    networking.firewall.extraStopCommands = ''
      ${ip6tables} -t nat -D POSTROUTING -j fox-exit-post 2>/dev/null || true
      ${ip6tables} -t nat -F fox-exit-post 2>/dev/null || true
      ${ip6tables} -t nat -X fox-exit-post 2>/dev/null || true
      ${iptables} -t nat -D POSTROUTING -j fox-exit-post 2>/dev/null || true
      ${iptables} -t nat -D PREROUTING -j fox-exit-pre 2>/dev/null || true
      for c in fox-exit-post fox-exit-pre; do
        ${iptables} -t nat -F $c 2>/dev/null || true
        ${iptables} -t nat -X $c 2>/dev/null || true
      done
    '';

    ##########################################################################
    # Health (fox-green's health heartbeat fails if either exit is broken)
    ##########################################################################

    fox.server.monitoring.watchUnits = [ "netbird-direct.service" "wireguard-wg-mullvad.service" "mullvad-rotate.service" ];
    fox.server.monitoring.extraChecks = ''
      # Keepalives every 25 s mean a handshake at least every ~2 minutes.
      # mullvad-watch replaces a dead server within ~2 minutes, so 5 minutes
      # without one means switching servers isn't helping.
      hs=$(${wg} show wg-mullvad latest-handshakes 2>/dev/null | awk '{print $2}' | head -n 1)
      if [ -z "$hs" ] || [ $(( $(date +%s) - hs )) -gt 300 ]; then
        problems+=("mullvad exit: no handshake with Mullvad in 5 min")
      fi
      # Without the rules, phone traffic would skip Mullvad and leave unprotected.
      for v in -4 -6; do
        ${ip} $v rule show priority 100 | ${grep} -q 'iif wt0 lookup ${table}' \
          || problems+=("mullvad exit: routing rule missing ($v)")
        ${ip} $v route show table ${table} | ${grep} -q '^blackhole default' \
          || problems+=("mullvad exit: kill switch route missing ($v)")
      done
      ${ip} -n ${ns} route show default 2>/dev/null | ${grep} -q . \
        || problems+=("direct exit: namespace has no way out")
    '';
  }
  (mullvadRotate {
    iface = "wg-mullvad";
    inherit (m) country city;
    inherit table;
    everyHours = m.rotateEveryHours;
    inherit fallbackRelays;
    after = [ "mullvad-exit-routing.service" ];
  })
  ];
}
