# Qubes-style VMs with microvm.nix (https://microvm-nix.github.io/microvm.nix/).
# Each VM is a NixOS config below. A VM sees only its own programs (built into
# a read-only image, not the host's whole /nix/store) and keeps nothing between
# boots unless it has a volume: a disposable.
#
#   sudo systemctl start microvm@untrusted    boot it (console: journalctl -fu microvm@untrusted)
#   sudo systemctl stop microvm@untrusted     power off; everything inside is gone
#   microvm -l                                list VMs and whether they're out of date
#
# Windows: an app in a VM talks Wayland to `waypipe server`, which sends it
# over vsock (a VM-to-host channel, not a network) to the host. There,
# waypipe-gate checks which VM is calling, and that VM's `waypipe client` puts
# the window on Hyprland with "[<vm>] " in front of its title. hypr/rules.lua
# colours the border by that label. The label is added on the host, so a VM
# can't pick it.
#
# Launchers: vm-open starts the VM if needed and sends an app name to the VM's
# vsock port 6000; the VM opens only names in its `apps`.
{ inputs, pkgs, lib, ... }:
let
  # cid: the VM's vsock address (the host assigns it; a VM can't fake it).
  # Its windows arrive on host port 5000 + cid.
  # apps: what the VM may open, name -> command.
  # launchers: entries in the app launcher, "<vm>: <label>".
  vms = {
    untrusted = {
      cid = 3;
      apps = {
        terminal = [ "${pkgs.foot}/bin/foot" ];
        mullvad-browser = [ (lib.getExe pkgs.mullvad-browser) ];
      };
      launchers = [
        { app = "terminal"; label = "Terminal"; icon = "utilities-terminal"; }
        { app = "mullvad-browser"; label = "Mullvad Browser"; icon = "mullvad-browser"; }
      ];
    };
    sys-net = {
      cid = 4;
      apps.wifi = [ "${pkgs.foot}/bin/foot" "${pkgs.networkmanager}/bin/nmtui" ];
      launchers = [ { app = "wifi"; label = "Wi-Fi"; icon = "network-wireless"; } ];
    };
  };
  port = vm: toString (5000 + vm.cid);

  # The host <-> sys-net link: a point-to-point /30.
  sysNetAddr = "10.137.0.1";
  hostAddr = "10.137.0.2";
  # microvm's tap-up creates the tap owned by this user; NetworkManager's
  # profile must name the same owner to take the device over.
  microvmUid = 988;

  vmOpen = pkgs.writeShellApplication {
    name = "vm-open";
    runtimeInputs = [ pkgs.socat pkgs.systemd pkgs.libnotify ];
    text = ''
      # vm-open <vm> <cid> <app>: start the VM if it isn't running, then ask
      # it for the app, retrying while it boots.
      vm=$1 cid=$2 app=$3
      systemctl start "microvm@$vm.service"
      for _ in $(seq 60); do
        printf '%s\n' "$app" | socat -u - "VSOCK-CONNECT:$cid:6000" 2>/dev/null && exit 0
        sleep 0.5
      done
      notify-send "$vm VM" "Couldn't open $app: the VM didn't answer within 30 seconds."
      exit 1
    '';
  };

  # The Wi-Fi card (IOMMU group 6, alone in it).
  wifiPci = "0000:00:14.3";

  # Escape hatch: sudo wifi-to-host gives the card back to the host until the
  # next boot (sys-net starts at boot and takes it again).
  wifiToHost = pkgs.writeShellApplication {
    name = "wifi-to-host";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      systemctl stop microvm@sys-net.service
      d=/sys/bus/pci/devices/${wifiPci}
      echo > "$d/driver_override"
      if [ -e "$d/driver" ]; then echo ${wifiPci} > "$d/driver/unbind"; fi
      echo ${wifiPci} > /sys/bus/pci/drivers_probe
      echo "Wi-Fi is back on the host (driver: $(basename "$(readlink "$d/driver")"))."
      echo "Pick a network with: nmtui"
    '';
  };

  # What every VM has: its vsock address, a plain user, and the app listener.
  guestBase = name: vm: {
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      vsock.cid = vm.cid;
    };
    networking.hostName = name;
    networking.useDHCP = false;

    # Console logs straight in as root (journalctl -fu microvm@<vm> shows it).
    services.getty.autologinUser = "root";

    # Apps run as this plain user, never root. Linger gives it /run/user/1000.
    users.users.user = { isNormalUser = true; uid = 1000; linger = true; };
    fonts.packages = [ pkgs.dejavu_fonts ];

    # Only the host can reach this port: VMs can't talk to each other over vsock.
    systemd.sockets.app-launch = {
      wantedBy = [ "sockets.target" ];
      socketConfig = { ListenStream = "vsock::6000"; Accept = true; };
    };
    systemd.services."app-launch@".serviceConfig = {
      User = "user";
      StandardInput = "socket";
      StandardOutput = "null";
      StandardError = "journal";
      Environment = "XDG_RUNTIME_DIR=/run/user/1000";
      ExecStart = pkgs.writeShellScript "app-launch" ''
        read -r -t 5 name || exit 1
        case "$name" in
        ${lib.concatStrings (lib.mapAttrsToList (n: cmd: "  ${n}) set -- ${lib.escapeShellArgs cmd} ;;\n") vm.apps)}
          *) echo "refused unknown app '$name'" >&2; exit 1 ;;
        esac
        exec </dev/null ${pkgs.waypipe}/bin/waypipe --no-gpu --vsock -s 2:${port vm} server -- "$@"
      '';
    };

    system.stateVersion = "26.05";
  };
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  # Kernel modules are locked after boot (core/hardening.nix), so these load
  # now: vsock for windows, VFIO for handing the Wi-Fi card to sys-net.
  boot.kernelModules = [ "vhost_vsock" "vfio" "vfio_pci" "vfio_iommu_type1" ];

  users.users.microvm.uid = microvmUid;

  environment.systemPackages = [ vmOpen wifiToHost ] ++ lib.concatLists (lib.mapAttrsToList (name: vm:
    map (l: pkgs.makeDesktopItem {
      name = "vm-${name}-${l.app}";
      desktopName = "${name}: ${l.label}";
      exec = "vm-open ${name} ${toString vm.cid} ${l.app}";
      inherit (l) icon;
    }) vm.launchers) vms);

  # Your user may start, stop and restart VMs without the PIN and touch, so a
  # launcher click doesn't ask. Only microvm@ units, only those three verbs.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "arlo" &&
          /^microvm@[a-z0-9-]+\.service$/.test(action.lookup("unit")) &&
          ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0)
        return polkit.Result.YES;
    });
  '';

  # Host side of the windows, per VM, in your graphical session.
  systemd.user.services = lib.concatMapAttrs (name: vm: {
    "waypipe-${name}" = {
      description = "Windows from the ${name} VM";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/waypipe-${name}.sock";
        ExecStart = "${pkgs.waypipe}/bin/waypipe --no-gpu --title-prefix '[${name}] ' -s %t/waypipe-${name}.sock client";
      };
    };
    "waypipe-${name}-gate@".serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/waypipe-gate.sh} %i ${toString vm.cid} %t/waypipe-${name}.sock";
      StandardInput = "socket";
      StandardError = "journal";
      Environment = "PATH=${pkgs.socat}/bin";
    };
  }) vms;
  systemd.user.sockets = lib.concatMapAttrs (name: vm: {
    "waypipe-${name}-gate" = {
      description = "Window connections from VMs, for the ${name} VM";
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      socketConfig = { ListenStream = "vsock::${port vm}"; Accept = true; };
    };
  }) vms;

  # The host's end of the sys-net link, and its way to the internet: the Wi-Fi
  # card lives in sys-net, which shares its connection (NAT). microvm creates
  # the tap when sys-net starts; NetworkManager gives it the address.
  # Metric 700: if the card is ever back on the host (wifi-to-host), the
  # host's own Wi-Fi (600) wins.
  networking.networkmanager.ensureProfiles.profiles.sys-net = {
    # autoconnect off: NM would recreate the tap the moment microvm's tap-up
    # deletes it, and tap-up then fails (busy). The ExecStartPost below connects it.
    connection = { id = "sys-net"; type = "tun"; interface-name = "vm-sysnet"; autoconnect = false; };
    tun = { mode = 2; owner = toString microvmUid; vnet-hdr = true; multi-queue = true; };
    ipv4 = {
      method = "manual";
      address1 = "${hostAddr}/30,${sysNetAddr}";
      route-metric = 700;
      # Mullvad replaces this while connected; it's for apps outside the tunnel.
      dns = "9.9.9.9;";
    };
    ipv6.method = "disabled";
  };

  # Stop sys-net before suspend and start it on wake, so the Wi-Fi card is
  # never inside a VM across a suspend (passed-through cards often don't wake).
  systemd.services.sys-net-sleep = {
    description = "Stop sys-net before suspend, start it after";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemctl stop microvm@sys-net.service";
      ExecStop = "${pkgs.systemd}/bin/systemctl start --no-block microvm@sys-net.service";
    };
  };
  # microvm deletes and recreates the tap on every sys-net start, so connect it
  # once the tap exists. "-": a failure here must not stop sys-net from starting.
  systemd.services."microvm-tap-interfaces@sys-net".serviceConfig.ExecStartPost =
    "-" + pkgs.writeShellScript "sys-net-link-up" ''
      for _ in $(seq 20); do
        ${pkgs.networkmanager}/bin/nmcli connection up sys-net && exit 0
        sleep 0.5
      done
      exit 1
    '';

  microvm.vms =lib.mapAttrs (name: vm: {
    autostart = false;
    config = guestBase name vm;
  }) vms // {
    sys-net = {
      # The host's internet comes through it, so it starts at boot.
      autostart = true;
      config = {
        imports = [ (guestBase "sys-net" vms.sys-net) ];
        microvm = {
          mem = 768; # MiB
          interfaces = [ { type = "tap"; id = "vm-sysnet"; mac = "02:00:00:00:04:01"; } ];
          devices = [ { bus = "pci"; path = wifiPci; } ];
          # Saved Wi-Fi networks survive reboots: /var/lib/microvms/sys-net/wifi.img
          volumes = [ { image = "wifi.img"; mountPoint = "/etc/NetworkManager/system-connections"; size = 16; } ];
        };
        hardware.enableRedistributableFirmware = true;  # the card's iwlwifi firmware
        hardware.wirelessRegulatoryDatabase = true;

        # Fixed names, so NAT can name them: the link to the host, and the card.
        systemd.network.links."10-uplink" = {
          matchConfig.MACAddress = "02:00:00:00:04:01";
          linkConfig.Name = "uplink";
        };
        systemd.network.links."10-wifi" = {
          matchConfig.Driver = "iwlwifi";
          linkConfig.Name = "wifi";
        };
        networking.nat = { enable = true; internalInterfaces = [ "uplink" ]; externalInterface = "wifi"; };

        networking.networkmanager.enable = true;
        # Same as the host had: a different MAC address per network.
        networking.networkmanager.wifi.macAddress = "stable-ssid";
        # nmtui runs as `user`; this group may change networks without a password.
        users.users.user.extraGroups = [ "networkmanager" ];
        networking.networkmanager.ensureProfiles.profiles.uplink = {
          connection = { id = "uplink"; type = "ethernet"; };
          ethernet.mac-address = "02:00:00:00:04:01";
          ipv4 = { method = "manual"; address1 = "${sysNetAddr}/30"; };
          ipv6.method = "disabled";
        };
      };
    };
  };
}
