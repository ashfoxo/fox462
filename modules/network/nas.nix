# The home NAS ("Ark", an SMB share that can't run NetBird).
#
# It is mounted only while this machine is on the home network, and
# unmounted the moment it leaves: nothing talks to Ark anywhere else. "Home"
# is the Wi-Fi network fox.nas.wifiSsid and/or any wired connection
# (fox.nas.wired). Settings are in modules/options.nix.
#
# While home, Mullvad's "allow local network" is turned on so Ark is
# reachable; away from home it is turned off again (Mullvad's default), so
# every other network stays fully tunnelled.
#
# How it works: NetworkManager runs a tiny dispatcher on every connect and
# disconnect, which restarts fox-nas-sync. That script looks at the connected
# devices, then mounts or unmounts the share and flips Mullvad's setting.
# It also runs once at boot.
#
# Needs these keys in secrets.yaml (./sops.sh secrets/secrets.yaml):
#   nas-username   - the NAS account you use from Windows
#   nas-password   - its password
{ config, lib, pkgs, utils, ... }:

let
  cfg = config.fox.nas;
  mountUnit = "${utils.escapeSystemdPath cfg.mountPoint}.mount";

  sync = pkgs.writeShellApplication {
    name = "fox-nas-sync";
    runtimeInputs = [ pkgs.networkmanager pkgs.systemd pkgs.mullvad pkgs.util-linux ];
    text = ''
      home=0
      while IFS=: read -r dev type state; do
        [ "$state" = connected ] || continue
        case "$type" in
          wifi)
            ${lib.optionalString (cfg.wifiSsid != null) ''
              uuid=$(nmcli -g GENERAL.CON-UUID device show "$dev" || true)
              ssid=$(nmcli -g 802-11-wireless.ssid connection show uuid "$uuid" || true)
              if [ "$ssid" = ${lib.escapeShellArg cfg.wifiSsid} ]; then home=1; fi
            ''}
            : ;;
          ethernet)
            ${lib.optionalString cfg.wired "home=1"}
            : ;;
        esac
      done < <(nmcli -t -f DEVICE,TYPE,STATE device)

      if [ "$home" = 1 ]; then
        mullvad lan set allow || true
        systemctl start ${lib.escapeShellArg mountUnit} || true
      else
        systemctl stop ${lib.escapeShellArg mountUnit} || true
        # The NAS is gone, so a normal unmount can hang or say "busy".
        if mountpoint -q ${lib.escapeShellArg cfg.mountPoint}; then
          umount -l ${lib.escapeShellArg cfg.mountPoint} || true
        fi
        mullvad lan set block || true
      fi
    '';
  };
in
lib.mkIf cfg.enable {
  sops.secrets.nas-username = { };
  sops.secrets.nas-password = { };
  # Root-only file in /run, so the password stays out of the Nix store.
  sops.templates."nas-credentials".content = ''
    username=${config.sops.placeholder.nas-username}
    password=${config.sops.placeholder.nas-password}
  '';

  environment.systemPackages = [ pkgs.cifs-utils ];

  # noauto: never mounted at boot or on first access, only by fox-nas-sync.
  fileSystems.${cfg.mountPoint} = {
    device = "//${cfg.host}/${cfg.share}";
    fsType = "cifs";
    options = [
      "noauto" "nofail" "_netdev"
      "credentials=${config.sops.templates."nas-credentials".path}"
      "uid=arlo" "gid=users" "file_mode=0600" "dir_mode=0700"
      "vers=3.0" "iocharset=utf8"
      "nodev" "nosuid" "noexec"
      "soft"                       # fail instead of freezing apps if Ark vanishes
      "x-systemd.mount-timeout=20"
    ];
  };

  systemd.services.fox-nas-sync = {
    description = "Mount the NAS at home, unmount elsewhere";
    after = [ "NetworkManager.service" "mullvad-daemon.service" ];
    wants = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe sync;
    };
  };

  # Re-check on every connect and disconnect. --no-block: NetworkManager
  # kills dispatcher scripts that take long, and a mount can.
  networking.networkmanager.dispatcherScripts = [{
    type = "basic";
    source = pkgs.writeShellScript "fox-nas-dispatch" ''
      case "$2" in
        up|down) exec ${pkgs.systemd}/bin/systemctl restart --no-block fox-nas-sync.service ;;
      esac
    '';
  }];
}
