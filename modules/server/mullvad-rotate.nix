# Keep a WireGuard interface on a random active Mullvad server: a new one at
# start, every `everyHours` on the hour, and whenever nothing answers through
# the current one for two minutes. One key works on every Mullvad server, so
# only the peer changes. Used by services/exit-nodes.nix (fox-green's phone
# exit) and services/torrent.nix (fox-red's qbt namespace).
#
#   mullvadRotate = import ../mullvad-rotate.nix { inherit config lib pkgs srv; };
#   config = lib.mkMerge [ { ... } (mullvadRotate { iface = "wg-x"; ... }) ];
#
# Returns the units (<name>-rotate and <name>-watch, with timers). The
# interface must exist without peers; the rotate unit adds the peer and the
# default routes, so until it has run, nothing leaves through the interface.
{ config, lib, pkgs, srv }:
{ name ? "mullvad"          # unit and script prefix
, iface                     # WireGuard interface, e.g. wg-mullvad
, country                   # Mullvad country code, e.g. "de"
, city ? null               # Mullvad city code; null = anywhere in the country
, table ? null              # routing table for the default routes; null = main
, everyHours                # scheduled switch every N hours, on the hour
, fallbackRelays            # "hostname pubkey ipv4" lines, for when no list can be had
, after ? [ ]               # extra units both scripts must start after
, serviceConfig ? { }       # extra settings for both units (e.g. a network namespace)
}:
let
  state = "/var/lib/${name}-rotate";
  tableArg = lib.optionalString (table != null) " table ${table}";

  # Point the interface at a random Mullvad server in the chosen place, other
  # than the current one. Usage: <name>-rotate [reason]; "unreachable" also
  # alerts.
  rotate = pkgs.writeShellScript "${name}-rotate" ''
    set -u
    PATH=${lib.makeBinPath (with pkgs; [ coreutils gnugrep jq curl util-linux iproute2 wireguard-tools ])}
    reason=''${1:-scheduled}
    mkdir -p ${state}
    exec 9>${state}/lock
    flock -w 60 9 || exit 0
    ip link show ${iface} >/dev/null 2>&1 || { echo "${iface} is not up" >&2; exit 1; }

    # Mullvad's server list, refreshed every time. If it can't be fetched,
    # the last good copy; if there's none, the few built in above.
    if curl -fsS -m 20 https://api.mullvad.net/www/relays/wireguard/ -o ${state}/relays.new \
       && jq -e 'type == "array" and length > 0' ${state}/relays.new >/dev/null 2>&1; then
      mv ${state}/relays.new ${state}/relays.json
    fi
    servers=""
    [ -s ${state}/relays.json ] && servers=$(jq -r \
      '.[] | select(.active and .country_code == "${country}"${lib.optionalString (city != null) " and .city_code == \"${city}\""})
           | "\(.hostname) \(.pubkey) \(.ipv4_addr_in)"' ${state}/relays.json)
    [ -n "$servers" ] || servers=$(printf '%b' "${fallbackRelays}")

    current=$(wg show ${iface} peers)
    pick=""
    [ -n "$current" ] && pick=$(printf '%s\n' "$servers" | grep -v -F "$current" | shuf -n 1)
    [ -n "$pick" ] || pick=$(printf '%s\n' "$servers" | shuf -n 1)
    read -r host key addr <<<"$pick"

    # Add the new server before removing the old one, so the tunnel is never
    # without a peer. The routes are dev routes, so they don't change.
    wg set ${iface} peer "$key" endpoint "$addr:51820" \
      allowed-ips 0.0.0.0/0,::/0 persistent-keepalive 25
    for p in $current; do
      [ "$p" = "$key" ] || wg set ${iface} peer "$p" remove
    done
    ip route replace default dev ${iface}${tableArg}
    ip -6 route replace default dev ${iface}${tableArg}
    echo 0 > ${state}/fails

    old=$(cat ${state}/current 2>/dev/null || echo none)
    echo "$host" > ${state}/current
    echo "Mullvad server: $old -> $host ($reason)"
    if [ "$reason" = unreachable ]; then
      ${srv.notify} "${config.networking.hostName}: Mullvad server switched" \
        "$old stopped answering; now on $host." low
    fi
  '';

  # Every minute: can anything be reached through the tunnel? Mullvad's own
  # resolver (10.64.0.1) answers ping on every server; 1.1.1.1 is the second
  # opinion. Two failed minutes in a row and the server is replaced.
  watch = pkgs.writeShellScript "${name}-watch" ''
    set -u
    PATH=${lib.makeBinPath (with pkgs; [ coreutils iproute2 iputils ])}
    ip link show ${iface} >/dev/null 2>&1 || exit 0
    if ping -I ${iface} -c 1 -W 3 10.64.0.1 >/dev/null 2>&1 \
       || ping -I ${iface} -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
      echo 0 > ${state}/fails
      exit 0
    fi
    n=$(( $(cat ${state}/fails 2>/dev/null || echo 0) + 1 ))
    echo "$n" > ${state}/fails
    echo "nothing answered through ${iface} ($n in a row)"
    [ "$n" -ge 2 ] && exec ${rotate} unreachable
    exit 0
  '';
in
{
  assertions = [{
    assertion = everyHours >= 1 && everyHours <= 24 && lib.mod 24 everyHours == 0;
    message = "${name}: everyHours must divide 24 (1, 2, 3, 4, 6, 8, 12 or 24), got ${toString everyHours}.";
  }];

  systemd.services."${name}-rotate" = {
    description = "Move ${iface} to a random Mullvad server";
    wantedBy = [ "wireguard-${iface}.service" ];
    after = [ "wireguard-${iface}.service" "network-online.target" ] ++ after;
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rotate} scheduled";
      StateDirectory = "${name}-rotate";
    } // serviceConfig;
  };
  # On the hour (00:00, then every everyHours), not relative to boot.
  systemd.timers."${name}-rotate" = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 00/${toString everyHours}:00:00";
  };

  systemd.services."${name}-watch" = {
    description = "Replace ${iface}'s Mullvad server when nothing answers through it";
    after = [ "${name}-rotate.service" ] ++ after;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${watch}";
      StateDirectory = "${name}-rotate";
    } // serviceConfig;
  };
  systemd.timers."${name}-watch" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3m";
      OnUnitActiveSec = "1m";
    };
  };
}
