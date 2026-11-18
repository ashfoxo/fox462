# Qubes-style VMs with microvm.nix (https://microvm-nix.github.io/microvm.nix/).
# Each VM is a NixOS config below. A VM sees only its own programs (built into
# a read-only image, not the host's whole /nix/store) and has no disk of its
# own, so everything it writes is gone when it stops: a disposable.
#
#   sudo systemctl start microvm@untrusted    boot it (console: journalctl -fu microvm@untrusted)
#   sudo systemctl stop microvm@untrusted     power off; everything inside is gone
#   microvm -l                                list VMs and whether they're out of date
#
# Windows: an app in the VM talks Wayland to `waypipe server`, which sends it
# over vsock (a VM-to-host channel, not a network) to the host. There,
# waypipe-gate checks which VM is calling, and `waypipe client` puts the window
# on Hyprland with "[untrusted] " in front of its title. hypr/rules.lua colours
# the border by that label. The label is added on the host, so a VM can't
# pick it.
{ inputs, pkgs, lib, ... }:
let
  # The VM's vsock address (the host assigns it; a VM can't fake it) and the
  # host port its windows arrive on.
  cid = 3;
  port = 5003;

  # Apps the VM will open, by the name the host asks for.
  apps = {
    terminal = "${pkgs.foot}/bin/foot";
    mullvad-browser = lib.getExe pkgs.mullvad-browser;
  };

  # vm-open <vm> <cid> <app>: start the VM if it isn't running, then ask it
  # for the app, retrying while it boots.
  vmOpen = pkgs.writeShellApplication {
    name = "vm-open";
    runtimeInputs = [ pkgs.socat pkgs.systemd pkgs.libnotify ];
    text = ''
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
  launcher = app: label: icon: pkgs.makeDesktopItem {
    name = "vm-untrusted-${app}";
    desktopName = "untrusted: ${label}";
    exec = "vm-open untrusted ${toString cid} ${app}";
    inherit icon;
  };
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  environment.systemPackages = [
    vmOpen
    (launcher "terminal" "Terminal" "utilities-terminal")
    (launcher "mullvad-browser" "Mullvad Browser" "mullvad-browser")
  ];

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

  # Kernel modules are locked after boot (core/hardening.nix), so vsock loads now.
  boot.kernelModules = [ "vhost_vsock" ];

  # Host side of the windows, in your graphical session.
  systemd.user.services.waypipe-untrusted = {
    description = "Windows from the untrusted VM";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/waypipe-untrusted.sock";
      ExecStart = "${pkgs.waypipe}/bin/waypipe --no-gpu --title-prefix '[untrusted] ' -s %t/waypipe-untrusted.sock client";
    };
  };
  systemd.user.sockets.waypipe-untrusted-gate = {
    description = "Window connections from VMs, for the untrusted VM";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    socketConfig = {
      ListenStream = "vsock::${toString port}";
      Accept = true;
    };
  };
  systemd.user.services."waypipe-untrusted-gate@" = {
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/waypipe-gate.sh} %i ${toString cid} %t/waypipe-untrusted.sock";
      StandardInput = "socket";
      StandardError = "journal";
      Environment = "PATH=${pkgs.socat}/bin";
    };
  };

  # Not at boot; it runs when you start it.
  microvm.vms.untrusted.autostart = false;
  microvm.vms.untrusted.config = {
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 1024; # MiB
      vsock.cid = cid;
    };

    networking.hostName = "untrusted";
    # No network at all yet; sys-net comes later.
    networking.useDHCP = false;

    # Console logs straight in as root: the VM is disposable and offline.
    services.getty.autologinUser = "root";

    # Apps run as this plain user, never root. Linger gives it /run/user/1000.
    users.users.user = { isNormalUser = true; uid = 1000; linger = true; };
    fonts.packages = [ pkgs.dejavu_fonts ];

    # The host asks for an app by name on vsock port 6000 (vm-open, below).
    # Only names in `apps` run. Only the host can reach this port: VMs can't
    # talk to each other over vsock.
    systemd.sockets.app-launch = {
      wantedBy = [ "sockets.target" ];
      socketConfig = { ListenStream = "vsock::6000"; Accept = true; };
    };
    systemd.services."app-launch@" = {
      serviceConfig = {
        User = "user";
        StandardInput = "socket";
        StandardOutput = "null";
        StandardError = "journal";
        Environment = "XDG_RUNTIME_DIR=/run/user/1000";
        ExecStart = pkgs.writeShellScript "app-launch" ''
          read -r -t 5 name || exit 1
          case "$name" in
          ${lib.concatStrings (lib.mapAttrsToList (n: bin: "  ${n}) app=${bin} ;;\n") apps)}
            *) echo "refused unknown app '$name'" >&2; exit 1 ;;
          esac
          exec </dev/null ${pkgs.waypipe}/bin/waypipe --no-gpu --vsock -s 2:${toString port} server -- "$app"
        '';
      };
    };

    system.stateVersion = "26.05";
  };
}
