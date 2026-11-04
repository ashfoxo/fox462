# Threshold alerting for the host itself.
{ config, pkgs, lib, inputs, srv, ... }:
let
  inherit (srv) notify podman;
in
{
  # health-check.env: KUMA_PUSH_URL= for the health-check push monitor
  fox.server.secretNames = [ "health-check.env" ];
  fox.server.monitoring.watchUnits = [ "podman-*.service" ];

  # Threshold alerting. Kuma watches endpoints; this watches the host itself.
  # The restart-delta check exists because a unit in a restart loop never
  # reaches "failed" state, so nothing else here would see it.
  systemd.services.health-check = {
    description = "Host health thresholds -> ntfy + Kuma push";
    path = with pkgs; [ curl systemd coreutils gawk ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/run/secrets/health-check.env";
      StateDirectory = "health-check";
    };
    script = ''
      set -uo pipefail

      LOAD_MAX=2.0
      DISK_MAX=80
      MEM_MIN=400
      RESTART_MAX=3
      COOLDOWN=14400

      STATE=/var/lib/health-check
      problems=()

      LOAD15=$(awk '{print $3}' /proc/loadavg)
      if awk -v l="$LOAD15" -v t="$LOAD_MAX" 'BEGIN{exit !(l>t)}'; then
        problems+=("load15 $LOAD15 (max $LOAD_MAX)")
      fi

      DISK=$(df --output=pcent / | tail -1 | tr -dc '0-9')
      if [ "$DISK" -ge "$DISK_MAX" ]; then
        problems+=("disk / at ''${DISK}%")
      fi

      MEM=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
      if [ "$MEM" -lt "$MEM_MIN" ]; then
        problems+=("mem available ''${MEM}MB")
      fi

      FAILED=$(systemctl list-units --state=failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
      if [ -n "$FAILED" ]; then
        problems+=("failed: $FAILED")
      fi

      for unit in $(systemctl list-units --type=service --no-legend --plain ${lib.escapeShellArgs config.fox.server.monitoring.watchUnits} | awk '{print $1}'); do
        n=$(systemctl show -p NRestarts --value "$unit")
        f="$STATE/nr.$unit"
        prev=$(cat "$f" 2>/dev/null || echo "$n")
        echo "$n" > "$f"
        if [ $(( n - prev )) -ge "$RESTART_MAX" ]; then
          problems+=("$unit restarted $(( n - prev ))x in 5min")
        fi
      done

      STAMP="$STATE/last-alert"
      NOW=$(date +%s)

      if [ ''${#problems[@]} -gt 0 ]; then
        MSG=$(printf '%s\n' "''${problems[@]}")
        LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
        if [ $(( NOW - LAST )) -ge "$COOLDOWN" ]; then
          ${notify} "${config.networking.hostName}: health check" "$MSG" urgent
          echo "$NOW" > "$STAMP"
        fi
        curl -fsS -m 10 -G "$KUMA_PUSH_URL" \
          --data-urlencode "status=down" --data-urlencode "msg=$MSG" >/dev/null 2>&1 || true
      else
        if [ -f "$STAMP" ]; then
          ${notify} "${config.networking.hostName}: health recovered" "All checks clear." default
          rm -f "$STAMP"
        fi
        curl -fsS -m 10 -G "$KUMA_PUSH_URL" \
          --data-urlencode "status=up" --data-urlencode "msg=OK" >/dev/null 2>&1 || true
      fi
      exit 0
    '';
  };

  systemd.timers.health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "30s";
    };
  };
}
