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
{ config, inputs, pkgs, lib, utils, ... }:
let
  # cid: the VM's vsock address (the host assigns it; a VM can't fake it).
  # Its windows arrive on host port 5000 + cid.
  # apps: what the VM may open, name -> command.
  # launchers: entries in the app launcher, "<vm>: <label>".
  vms = {
    untrusted = {
      cid = 3;
      autoStop = true;
      apps = {
        terminal = [ "${pkgs.foot}/bin/foot" ];
        mullvad-browser = [ (lib.getExe pkgs.mullvad-browser) ];
      };
      launchers = [
        { app = "terminal"; label = "Terminal"; icon = "utilities-terminal"; }
        # Links clicked anywhere on the host open here (home/desktop/defaults.nix).
        { app = "mullvad-browser"; label = "Mullvad Browser"; icon = "mullvad-browser"; links = [ "http" "https" ]; }
      ];
    };
    sys-net = {
      cid = 4;
      pci = true; # has the Wi-Fi card, so its virtual NICs are PCI too
      apps.wifi = [ "${pkgs.foot}/bin/foot" "${pkgs.networkmanager}/bin/nmtui" ];
      launchers = [ { app = "wifi"; label = "Wi-Fi"; icon = "network-wireless"; } ];
    };
    sys-vpn = { cid = 5; apps = { }; launchers = [ ]; };
    calls = {
      cid = 6;
      autoStop = true;
      pci = true; # USB (the webcam) needs a PCI bus, so its NIC is PCI too
      audio = true;
      apps = {
        # Zoom without its bubblewrap FHS wrapper (the VM is the sandbox): the
        # unpacked binaries run through nix-ld, with the FHS library set
        # nixpkgs builds for it. Its Wayland support is patchy, so it gets a
        # private X server (xwayland-satellite), forwarded by waypipe like any
        # app; a fresh display number each launch, so a leftover one can't block it.
        zoom = [ "${pkgs.bash}/bin/sh" "-c" ''
          d=$(( $$ % 50 + 10 ))
          ${lib.getExe pkgs.xwayland-satellite} :$d &
          sleep 1
          export DISPLAY=:$d QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1
          export PATH=${pkgs.pulseaudio}/bin:$PATH
          export NIX_LD_LIBRARY_PATH=/run/opengl-driver/lib:${zoomDir}:${zoomDir}/Qt/lib:${pkgs.zoom-us.fhsenv}/usr/lib64
          exec ${zoomDir}/ZoomLauncher ''${APP_LINK:+"$APP_LINK"}
        '' ];
        telegram = [ (lib.getExe pkgs.telegram-desktop) ];
        vesktop = [ (lib.getExe pkgs.vesktop) "--ozone-platform=wayland" ];
      };
      launchers = [
        # Zoom meeting links (from Firefox's "Launch meeting") open here.
        { app = "zoom"; label = "Zoom"; icon = "Zoom"; links = [ "zoommtg" "zoomus" ]; }
        { app = "telegram"; label = "Telegram"; icon = "org.telegram.desktop"; }
        { app = "vesktop"; label = "Vesktop"; icon = "vesktop"; }
      ];
    };
    torrent = {
      cid = 7;
      autoStop = true;
      pci = true; # the ~/torrents share (virtiofs) needs PCI, so its NIC is PCI too
      # The torrent list is forgotten at power-off, as before; downloads land
      # in the host's ~/torrents (shared in).
      apps.qbittorrent = [ "${pkgs.bash}/bin/sh" "-c" ''
        c=$HOME/.config/qBittorrent/qBittorrent.conf
        mkdir -p "$(dirname "$c")"
        [ -e "$c" ] || printf '[BitTorrent]\nSession\\DefaultSavePath=/home/user/torrents\nSession\\TempPathEnabled=false\n' > "$c"
        exec ${lib.getExe pkgs.qbittorrent}
      '' ];
      launchers = [ { app = "qbittorrent"; label = "qBittorrent"; icon = "qbittorrent"; } ];
    };
    # Logged-in browsing and Matrix, behind sys-vpn. Its home is kept.
    personal = {
      cid = 8;
      trustClipboard = true;  # your own logins: shares the host clipboard, no Super+Shift+V
      autoStop = true;
      audio = true;
      apps = {
        librewolf = [ (lib.getExe librewolfLogins) ];
        # No keyring in the VM: Element keeps its database key in its profile,
        # on the VM's disk image (inside the host's encrypted disk).
        element = [ (lib.getExe pkgs.element-desktop) "--password-store=basic" "--ozone-platform=wayland" ];
      };
      launchers = [
        { app = "librewolf"; label = "LibreWolf"; icon = "librewolf"; }
        { app = "element"; label = "Element"; icon = "element"; }
      ];
    };
    # Hotel/airport Wi-Fi login pages: straight out through sys-net (no
    # Mullvad, which can't connect until you've logged in), thrown away after.
    portal = {
      cid = 9;
      autoStop = true;
      apps.login = [ (lib.getExe pkgs.firefox) "--private-window" "http://detectportal.firefox.com/canonical.html" ];
      launchers = [ { app = "login"; label = "Wi-Fi login page"; icon = "network-wireless"; } ];
    };
  };
  # The host's LibreWolf settings (home/desktop/sandboxes.nix), for personal.
  librewolfLogins = pkgs.librewolf.override {
    extraPrefs = ''
      lockPref("places.history.enabled", false);
      lockPref("browser.cache.disk.enable", false);
      lockPref("browser.cache.offline.enable", false);
      lockPref("browser.sessionstore.max_tabs_undo", 0);
      lockPref("browser.sessionstore.resume_from_crash", false);
      lockPref("browser.formfill.enable", false);
      lockPref("browser.download.manager.addToRecentDocs", false);
      lockPref("privacy.clearOnShutdown.cookies", false);
      lockPref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
      lockPref("network.cookie.lifetimePolicy", 0);
    '';
  };
  zoomDir = "${pkgs.zoom-us.unpacked}/opt/zoom";
  # Audio for VMs with audio = true: their PulseAudio clients reach the host's
  # PipeWire over vsock port 7000 + cid, through the same CID-checking gate.
  audioPort = vm: toString (7000 + vm.cid);
  # Webcams (lsusb-style ids), handed to the calls VM while it runs.
  webcams = [
    { vendor = "0c45"; product = "6a09"; } # built in
    { vendor = "04a9"; product = "3113"; } # Canon EOS R8 in UVC webcam mode
  ];
  port = vm: toString (5000 + vm.cid);

  # Links between VMs. Each is a pair of Unix datagram sockets in linkDir that
  # qemu joins directly: VM-to-VM traffic never touches the host's network
  # stack. `a` is the end nearer the internet (<net>.1), `b` the other (<net>.2).
  # Inside each VM the NIC is named after the link.
  links = {
    sysnet-vpn    = { id = "11"; a = "sys-net"; b = "sys-vpn";   net = "10.137.1"; };
    vpn-untrusted = { id = "12"; a = "sys-vpn"; b = "untrusted"; net = "10.137.2"; };
    sysnet-calls  = { id = "13"; a = "sys-net"; b = "calls";     net = "10.137.3"; };
    vpn-torrent   = { id = "14"; a = "sys-vpn"; b = "torrent";   net = "10.137.4"; };
    vpn-personal  = { id = "15"; a = "sys-vpn"; b = "personal";  net = "10.137.5"; };
    sysnet-portal = { id = "16"; a = "sys-net"; b = "portal";    net = "10.137.6"; };
  };
  # Each link's two sockets live in their own folder, group vml-<link>, so
  # only the two VMs on that link (each qemu runs as its own user, below) can
  # reach them.
  linkDir = "/run/microvm-links";
  # qemu's user per VM. sys-net stays `microvm`: microvm.nix hardcodes that
  # user for the tap device and the Wi-Fi card's VFIO node.
  vmUser = name: if name == "sys-net" then "microvm" else "vm-${name}";
  linkMac = l: side: "02:00:00:00:${l.id}:0${if side == "a" then "1" else "2"}";
  linkEnds = vmName: lib.concatLists (lib.mapAttrsToList (n: l:
    lib.optional (l.a == vmName) { name = n; link = l; me = "a"; peer = "b"; }
    ++ lib.optional (l.b == vmName) { name = n; link = l; me = "b"; peer = "a"; }) links);
  # An end's address, e.g. linkAddr "vpn-untrusted" "a" -> "10.137.2.1".
  linkAddr = n: side: "${links.${n}.net}.${if side == "a" then "1" else "2"}";

  # sys-vpn's Mullvad device: its Address line (not secret). The private key
  # is the sops secret mullvad-sysvpn-key.
  sysVpnAddresses = [ "10.65.80.225/32" "fc00:bbbb:bbbb:bb01::2:50e0/128" ];

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
      # vm-open <vm> <cid> <app> [link]: start the VM if it isn't running, then
      # ask it for the app (and the link to open), retrying while it boots.
      vm=$1 cid=$2 app=$3 link=''${4:-}
      systemctl start "microvm@$vm.service"
      for _ in $(seq 60); do
        printf '%s\n%s\n' "$app" "$link" | socat -u - "VSOCK-CONNECT:$cid:6000" 2>/dev/null && exit 0
        sleep 0.5
      done
      notify-send "$vm VM" "Couldn't open $app: the VM didn't answer within 30 seconds."
      exit 1
    '';
  };

  # The Wi-Fi card (IOMMU group 6, alone in it), and its vendor:device id.
  wifiPci = "0000:00:14.3";
  wifiId = "8086:02f0";
  # Fixed, so Element and LibreWolf in personal can read their own saved data.
  personalMachineId = "90c6c67b7f439599f8df4a80b432c580";

  vmClip = pkgs.writeShellApplication {
    name = "vm-clip";
    runtimeInputs = with pkgs; [ wl-clipboard socat jq libnotify config.programs.hyprland.package ];
    # VMs with trustClipboard share the host clipboard like host apps.
    text = "export VM_CLIP_TRUSTED=\"${toString (lib.attrNames (lib.filterAttrs (_: vm: vm.trustClipboard or false) vms))}\"\n" + builtins.readFile ../scripts/vm-clip.sh;
  };

  # Escape hatch: sudo wifi-to-host gives the card back to the host until the
  # next boot (sys-net starts at boot and takes it again).
  wifiToHost = pkgs.writeShellApplication {
    name = "wifi-to-host";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      systemctl stop microvm@sys-net.service
      d=/sys/bus/pci/devices/${wifiPci}
      # vfio-pci.ids (boot.kernelParams) would grab it again: name the driver.
      echo iwlwifi > "$d/driver_override"
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
      # One NIC per link this VM is on (see `links`).
      qemu.extraArgs = lib.concatMap (e: [
        "-netdev" "dgram,id=${e.name},local.type=unix,local.path=${linkDir}/${e.name}/${e.me},remote.type=unix,remote.path=${linkDir}/${e.name}/${e.peer}"
        "-device" "${if vm.pci or false then "virtio-net-pci" else "virtio-net-device"},netdev=${e.name},mac=${linkMac e.link e.me}"
      ]) (linkEnds name);
    };
    systemd.network.links = lib.listToAttrs (map (e: lib.nameValuePair "20-${e.name}" {
      matchConfig.MACAddress = linkMac e.link e.me;
      linkConfig.Name = e.name;
    }) (linkEnds name));
    networking.hostName = name;
    networking.useDHCP = false;

    # Console logs straight in as root (journalctl -fu microvm@<vm> shows it).
    services.getty.autologinUser = "root";
    # The VM's own log goes to that console too, so the host can read it.
    services.journald.extraConfig = ''
      ForwardToConsole=yes
      MaxLevelConsole=info
    '';

    # Apps run as this plain user, never root. Linger gives it /run/user/1000.
    users.users.user = { isNormalUser = true; uid = 1000; linger = true; };
    fonts.packages = [ pkgs.dejavu_fonts ];

    # Only the host can reach this port: VMs can't talk to each other over vsock.
    systemd.sockets.app-launch = {
      wantedBy = [ "sockets.target" ];
      socketConfig = { ListenStream = "vsock::6000"; Accept = true; };
    };
    systemd.services."app-launch@".requires = [ "user@1000.service" ];  # /run/user/1000
    systemd.services."app-launch@".after = [ "user@1000.service" ];
    systemd.services."app-launch@".serviceConfig = {
      User = "user";
      StandardInput = "socket";
      StandardOutput = "null";
      StandardError = "journal";
      Environment = [ "XDG_RUNTIME_DIR=/run/user/1000" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus" ];
      ExecStart = pkgs.writeShellScript "app-launch" ''
        read -r -t 5 name || exit 1
        # Optional link for the app: only the link types its launcher claims
        # (`links`, e.g. http(s) for Mullvad Browser, zoommtg for Zoom), and no
        # spaces, so nothing else can ride along. It's passed as one argument.
        read -r -t 1 APP_LINK || APP_LINK=
        schemes=
        case "$name" in
        ${lib.concatStrings (lib.mapAttrsToList (n: cmd: "  ${n}) set -- ${lib.escapeShellArgs cmd}; schemes='${lib.concatStringsSep "|" (lib.concatMap (l: lib.optionals (l.app == n) (l.links or [ ])) vm.launchers)}' ;;\n") vm.apps)}
          *) echo "refused unknown app '$name'" >&2; exit 1 ;;
        esac
        if [ -n "$APP_LINK" ]; then
          re="^($schemes)://[^[:space:]]+\$"
          if [ -z "$schemes" ] || ! [[ $APP_LINK =~ $re ]]; then
            echo "refused link '$APP_LINK'" >&2; exit 1
          fi
          set -- "$@" "$APP_LINK"
        fi
        export APP_LINK
        exec </dev/null ${pkgs.waypipe}/bin/waypipe --no-gpu --vsock -s 2:${port vm} server -- "$@"
      '';
    };

    system.stateVersion = "26.05";

    # A separate module, so it merges with the above instead of replacing
    # whole sections (`//` would drop the rest of `systemd`).
    imports = [
    # autoStop: when an app exits (e.g. Super+Q) and no other app is still
    # open, the VM powers off. "+": poweroff needs root, the app runs as user.
    (lib.optionalAttrs (vm.autoStop or false) {
      systemd.services."app-launch@".serviceConfig.ExecStopPost = "+" + pkgs.writeShellScript "stop-when-idle" ''
        sleep 3
        ${pkgs.systemd}/bin/systemctl list-units --plain --no-legend --state=active,activating 'app-launch@*.service' | grep -q . \
          || ${pkgs.systemd}/bin/systemctl poweroff
      '';
    })
    (lib.optionalAttrs (vm.audio or false) {
    # The usual PulseAudio socket, forwarded to the host's PipeWire. No shared
    # memory: it can't cross the VM boundary, so audio goes in-band.
    systemd.services.pulse-forward = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "user";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/user/1000/pulse";
        ExecStart = "${pkgs.socat}/bin/socat UNIX-LISTEN:/run/user/1000/pulse/native,fork,unlink-early,mode=600 VSOCK-CONNECT:2:${audioPort vm}";
        Restart = "always";
        RestartSec = 2;
      };
      # /run/user/1000 must exist first (made by user@1000, started by linger).
      requires = [ "user@1000.service" ];
      after = [ "user@1000.service" ];
    };
    environment.etc."pulse/client.conf".text = "enable-shm = no\n";
    }) ];
  };
in
{
  imports = [
    inputs.microvm.nixosModules.host
    {
      systemd.user.services.vm-clip = {
        description = "Keep the host clipboard away from VM windows";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = { ExecStart = "${vmClip}/bin/vm-clip watch"; Restart = "always"; RestartSec = 2; };
      };
    }
    {
      systemd.services = lib.concatMapAttrs (name: vm: {
        "microvm@${name}".serviceConfig = {
          # Link sockets must be writable by the VM at the other end (same group).
          UMask = "0007";
        } // lib.optionalAttrs (name != "sys-net") {
          # Its own user: a qemu escape lands in one VM's files, not all of them.
          User = lib.mkForce (vmUser name);
          ExecStartPre = "+${pkgs.coreutils}/bin/chown -hR ${vmUser name}:kvm /var/lib/microvms/${name}";
        } // lib.optionalAttrs (vm.autoStop or false) {
          # VMs that power themselves off when idle must stay off: restart them
          # only after a crash, not after a clean poweroff (microvm's default).
          Restart = lib.mkForce "on-failure";
        };
      }) vms;
    }
  ];

  # Kernel modules are locked after boot (core/hardening.nix), so these load
  # now: vsock for windows, VFIO for handing the Wi-Fi card to sys-net.
  boot.kernelModules = [ "vhost_vsock" "vfio" "vfio_pci" "vfio_iommu_type1" ];
  # VFIO claims the Wi-Fi card in the initrd, before the host's iwlwifi driver
  # ever touches it. (wifi-to-host overrides this until the next boot.)
  boot.initrd.kernelModules = [ "vfio" "vfio_pci" "vfio_iommu_type1" ];
  boot.kernelParams = [ "vfio-pci.ids=${wifiId}" ];

  users.users = {
    microvm = { uid = microvmUid; extraGroups = map (e: "vml-${e.name}") (linkEnds "sys-net"); };
  } // lib.mapAttrs' (name: _: lib.nameValuePair (vmUser name) {
    isSystemUser = true;
    group = "kvm";
    extraGroups = map (e: "vml-${e.name}") (linkEnds name);
  }) (removeAttrs vms [ "sys-net" ]);
  users.groups = lib.mapAttrs' (n: _: lib.nameValuePair "vml-${n}" { }) links;

  systemd.tmpfiles.rules = [ "d ${linkDir} 0755 root root -" ]
    ++ lib.mapAttrsToList (n: _: "d ${linkDir}/${n} 0770 root vml-${n} -") links;

  # sys-vpn's Mullvad key, handed into the VM as a systemd credential.
  sops.secrets.mullvad-sysvpn-key.owner = vmUser "sys-vpn";

  # Qubes-style clipboard (scripts/vm-clip.sh): a VM only gets what you hand
  # it with Super+Shift+V, and only gives what you take with Super+Shift+C.
  # (The user service is in `imports` above, next to the other host units.)

  environment.systemPackages = [ vmOpen wifiToHost vmClip ] ++ lib.concatLists (lib.mapAttrsToList (name: vm:
    map (l: pkgs.makeDesktopItem {
      name = "vm-${name}-${l.app}";
      desktopName = l.label;  # just the app's name; the border colour shows the VM
      exec = "vm-open ${name} ${toString vm.cid} ${l.app}" + lib.optionalString (l ? links) " %u";
      mimeTypes = map (s: "x-scheme-handler/${s}") (l.links or [ ]);
      inherit (l) icon;
    }) vm.launchers) vms);

  # Link types a VM app handles open there by default, not in a host app
  # (the host's own Zoom claims zoommtg too).
  xdg.mime.defaultApplications = lib.mkMerge (lib.concatLists (lib.mapAttrsToList (name: vm:
    map (l: lib.genAttrs (map (s: "x-scheme-handler/${s}") (l.links or [ ])) (_: "vm-${name}-${l.app}.desktop"))
      vm.launchers) vms));

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
  } // lib.optionalAttrs (vm.audio or false) {
    "pulse-${name}-gate@".serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/waypipe-gate.sh} %i ${toString vm.cid} %t/pulse/native";
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
  } // lib.optionalAttrs (vm.audio or false) {
    "pulse-${name}-gate" = {
      description = "Audio connections from VMs, for the ${name} VM";
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      socketConfig = { ListenStream = "vsock::${audioPort vm}"; Accept = true; };
    };
  }) vms;

  # qemu (as calls' own user) opens the webcams through libusb while calls runs.
  services.udev.extraRules = lib.concatMapStrings (w: ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="${w.vendor}", ATTR{idProduct}=="${w.product}", OWNER="${vmUser "calls"}"
  '') webcams;

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
        imports = [
          (guestBase "sys-net" vms.sys-net)
          # One static NM profile per link sys-net serves (sys-vpn, calls).
          {
            networking.networkmanager.ensureProfiles.profiles = lib.listToAttrs (map (e: lib.nameValuePair e.name {
              connection = { id = e.name; type = "ethernet"; interface-name = e.name; };
              ipv4 = { method = "manual"; address1 = "${linkAddr e.name "a"}/30"; };
              ipv6.method = "disabled";
            }) (linkEnds "sys-net"));
          }
        ];
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
        networking.nat = {
          enable = true;
          internalInterfaces = [ "uplink" ] ++ map (e: e.name) (linkEnds "sys-net");
          externalInterface = "wifi";
        };
        # Forward only out to Wi-Fi (and its replies): the host and sys-vpn
        # can't reach each other through sys-net.
        networking.firewall.extraCommands = ''
          iptables -F FORWARD
          iptables -P FORWARD DROP
          iptables -A FORWARD -o wifi -j ACCEPT
          iptables -A FORWARD -i wifi -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        '';
        # The login-page VM must use the Wi-Fi's own DNS: hotel login pages
        # work by answering every name with themselves. sys-net relays it.
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = { interface = [ "sysnet-portal" ]; bind-dynamic = true; resolv-file = "/run/NetworkManager/resolv.conf"; };
        };
        networking.firewall.interfaces.sysnet-portal = { allowedUDPPorts = [ 53 ]; allowedTCPPorts = [ 53 ]; };

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

    # sys-vpn: Mullvad for the VMs behind it, the same design as fox-red's
    # torrent namespace (server/services/torrent.nix):
    #
    #   sys-net ── sysnet-vpn ──┬── main namespace: only wg-mullvad's encrypted UDP
    #                           │   (and nothing else runs here)
    #                           └── namespace "vpn": wg-mullvad + the links to the
    #                               VMs behind it; wg-mullvad's routes are the
    #                               only way out (kill switch by construction)
    sys-vpn = {
      autostart = true;
      config = { config, ... }: {
        imports = [
          (guestBase "sys-vpn" vms.sys-vpn)
          (import ./server/mullvad-rotate.nix {
            inherit config lib pkgs;
            srv.notify = "${pkgs.coreutils}/bin/echo";  # no desktop in here; it goes to the log
          } {
            name = "vpn-mullvad";
            iface = "wg-mullvad";
            country = "ca";
            everyHours = 6;
            # Used only until a server list has been fetched through the tunnel.
            fallbackRelays = lib.concatStringsSep "\n" [
              "ca-mtr-wg-001 TUCaQc26/R6AGpkDUr8A8ytUs/e5+UVlIVujbuBwlzI= 146.70.198.66"
              "ca-tor-wg-001 HjcUGVDXWdrRkaKNpc/8494RM5eICO6DPyrhCtTv9Ws= 178.249.214.2"
              "ca-van-wg-201 hYbb2NQKB0g2RefngdHl3bfaLImUuzeVIv2i1VCVIlQ= 104.193.135.196"
            ];
            serviceConfig = {
              NetworkNamespacePath = "/run/netns/vpn";
              BindReadOnlyPaths = [ "/etc/netns/vpn/resolv.conf:/etc/resolv.conf" ];
            };
          })
        ];
        microvm = {
          mem = 384; # MiB
          credentialFiles.mullvad-key = "/run/secrets/mullvad-sysvpn-key";
        };

        networking.interfaces.sysnet-vpn.ipv4.addresses = [ { address = linkAddr "sysnet-vpn" "b"; prefixLength = 30; } ];
        networking.defaultGateway = { address = linkAddr "sysnet-vpn" "a"; interface = "sysnet-vpn"; };

        # Moves the links to the VMs behind sys-vpn into "vpn" and lets them out
        # through wg-mullvad only, masqueraded. Nothing forwards between them.
        systemd.services.netns-vpn = let
          downs = lib.filter (e: e.me == "a") (linkEnds "sys-vpn");
          devUnits = map (e: "sys-subsystem-net-devices-${utils.escapeSystemdPath e.name}.device") downs;
          ip = "${pkgs.iproute2}/bin/ip";
          ipt = "${ip} netns exec vpn ${pkgs.iptables}/bin/iptables";
        in {
          wantedBy = [ "multi-user.target" ];
          before = [ "wireguard-wg-mullvad.service" ];
          requires = devUnits;
          after = devUnits;
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
          script = ''
            set -eu
            [ -e /run/netns/vpn ] || ${ip} netns add vpn
            ${ip} -n vpn link set lo up
            ${ip} netns exec vpn ${pkgs.procps}/bin/sysctl -q -w net.ipv4.ip_forward=1
          '' + lib.concatMapStrings (e: ''
            ${ip} link show ${e.name} >/dev/null 2>&1 && ${ip} link set ${e.name} netns vpn
            ${ip} netns exec vpn ${pkgs.procps}/bin/sysctl -q -w net.ipv6.conf.${e.name}.disable_ipv6=1
            ${ip} -n vpn addr replace ${linkAddr e.name "a"}/30 dev ${e.name}
            ${ip} -n vpn link set ${e.name} up
          '') downs + ''
            ${ipt} -t nat -F POSTROUTING
            ${ipt} -t nat -A POSTROUTING -o wg-mullvad -j MASQUERADE
            ${ipt} -t mangle -F FORWARD
            ${ipt} -t mangle -A FORWARD -o wg-mullvad -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
            ${ipt} -F FORWARD
            ${ipt} -P FORWARD DROP
            ${ipt} -A FORWARD -o wg-mullvad -j ACCEPT
            ${ipt} -A FORWARD -i wg-mullvad -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
          '';
        };

        # The script-based WireGuard setup (like fox-red's): networkd's can't
        # place the interface in another namespace.
        networking.wireguard.useNetworkd = false;
        networking.wireguard.interfaces.wg-mullvad = {
          ips = sysVpnAddresses;
          privateKeyFile = "/run/credentials/@system/mullvad-key";
          interfaceNamespace = "vpn";
          # No peer here: vpn-mullvad-rotate picks a Canadian server and adds
          # the default routes inside "vpn".
          peers = [ ];
        };
        systemd.services.wireguard-wg-mullvad = {
          requires = [ "netns-vpn.service" ];
          after = [ "netns-vpn.service" ];
        };
        # Mullvad's resolver, reached through the tunnel.
        environment.etc."netns/vpn/resolv.conf".text = "nameserver 10.64.0.1\n";

        # Kill switch proof, in the log (journalctl -u microvm@sys-vpn | grep KILLSWITCH).
        # At boot, before any Mullvad server is set, nothing may leave "vpn";
        # then every 10 minutes, its only default routes must be wg-mullvad's.
        systemd.services.killswitch-boot = {
          wantedBy = [ "multi-user.target" ];
          requires = [ "wireguard-wg-mullvad.service" ];
          after = [ "wireguard-wg-mullvad.service" ];
          before = [ "vpn-mullvad-rotate.service" ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
          script = ''
            if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c1 -W2 9.9.9.9 >/dev/null 2>&1; then
              echo "KILLSWITCH FAIL: traffic left vpn with no Mullvad server set"; exit 1
            fi
            echo "KILLSWITCH OK: with no Mullvad server set, nothing leaves vpn"
          '';
        };
        systemd.services.killswitch-routes = {
          serviceConfig.Type = "oneshot";
          script = ''
            bad=$(for v in -4 -6; do ${pkgs.iproute2}/bin/ip $v -n vpn route show default; done | grep -v 'dev wg-mullvad' || true)
            if [ -n "$bad" ]; then echo "KILLSWITCH FAIL: vpn has a way out besides Mullvad: $bad"; exit 1; fi
            echo "KILLSWITCH OK: vpn's only way out is wg-mullvad"
          '';
        };
        systemd.timers.killswitch-routes = {
          wantedBy = [ "timers.target" ];
          timerConfig = { OnBootSec = "2min"; OnUnitActiveSec = "10min"; };
        };
      };
    };

    personal = {
      autostart = false;
      config = {
        imports = [ (guestBase "personal" vms.personal) ];
        microvm = {
          mem = 4096; # MiB
          vcpu = lib.mkForce 4;
          # Its home survives restarts: logins, Element's keys and history.
          volumes = [ { image = "home.img"; mountPoint = "/home/user"; size = 8192; } ];
        };
        systemd.tmpfiles.rules = [ "d /home/user 0700 user users -" ];
        hardware.graphics.enable = true;  # software OpenGL; Element (Electron) needs it
        environment.etc."machine-id".text = "${personalMachineId}\n";
        # Links clicked in Element open in LibreWolf, in here.
        environment.systemPackages = [ librewolfLogins pkgs.xdg-utils ];
        xdg.mime.defaultApplications = lib.genAttrs [ "x-scheme-handler/http" "x-scheme-handler/https" "text/html" ] (_: "librewolf.desktop");
        networking.interfaces.vpn-personal.ipv4.addresses = [ { address = linkAddr "vpn-personal" "b"; prefixLength = 30; } ];
        networking.defaultGateway = { address = linkAddr "vpn-personal" "a"; interface = "vpn-personal"; };
        networking.nameservers = [ "10.64.0.1" ];
      };
    };

    portal = {
      autostart = false;
      config = {
        imports = [ (guestBase "portal" vms.portal) ];
        microvm.mem = 1536; # MiB
        networking.interfaces.sysnet-portal.ipv4.addresses = [ { address = linkAddr "sysnet-portal" "b"; prefixLength = 30; } ];
        networking.defaultGateway = { address = linkAddr "sysnet-portal" "a"; interface = "sysnet-portal"; };
        # The Wi-Fi's own DNS, relayed by sys-net.
        networking.nameservers = [ (linkAddr "sysnet-portal" "a") ];
      };
    };

    untrusted = {
      autostart = false;
      config = {
        imports = [ (guestBase "untrusted" vms.untrusted) ];
        # Not exactly 2048: qemu's microvm machine corrupts the initrd at that size.
        microvm.mem = 2560; # MiB; Mullvad Browser, and foot's 512 MiB drawing buffer through waypipe
        # Out through sys-vpn (Mullvad); Mullvad's resolver through the tunnel.
        networking.interfaces.vpn-untrusted.ipv4.addresses = [ { address = linkAddr "vpn-untrusted" "b"; prefixLength = 30; } ];
        networking.defaultGateway = { address = linkAddr "vpn-untrusted" "a"; interface = "vpn-untrusted"; };
        networking.nameservers = [ "10.64.0.1" ];
      };
    };

    # calls: Zoom, Telegram and Vesktop with the webcam and audio. Straight out
    # through sys-net, no Mullvad (Zoom was always outside it). The webcam and
    # microphone are usable by these apps whenever calls is running.
    calls = {
      autostart = false;
      config = {
        imports = [ (guestBase "calls" vms.calls) ];
        microvm = {
          mem = 3072; # MiB
          vcpu = lib.mkForce 4;  # video is encoded on the CPU here
          # PCI and USB on: the webcam needs a USB bus, and microvm.nix adds a PCI
          # USB controller too, which needs PCI. (q35 fails: microvm.nix adds the
          # webcam before its controller.)
          qemu.machineOpts = { accel = "kvm:tcg"; mem-merge = "on"; acpi = "on"; pit = "off"; pic = "off"; pcie = "on"; usb = "on"; };
          devices = map (w: { bus = "usb"; path = "vendorid=0x${w.vendor},productid=0x${w.product}"; }) webcams;
          # Zoom's login survives restarts, as on the host before.
          volumes = [ { image = "zoom.img"; mountPoint = "/home/user/.zoom"; size = 256; } ];
        };
        systemd.tmpfiles.rules = [ "d /home/user/.zoom 0700 user users -" ];
        users.users.user.extraGroups = [ "video" "audio" ];
        # The R8's mic input arrives here as a USB sound card, which Zoom can't
        # see (it only sees the host's audio). Relay it to the host's
        # "Canon-mic" input (modules/desktop/default.nix), which Zoom does see.
        # shortcut: retries every 5 s while the camera is unplugged; fine unless the journal noise bothers you.
        systemd.services.canon-mic = {
          wantedBy = [ "multi-user.target" ];
          requires = [ "pulse-forward.service" ];
          after = [ "pulse-forward.service" ];
          environment.PULSE_SERVER = "unix:/run/user/1000/pulse/native";
          script = ''
            ${pkgs.alsa-utils}/bin/arecord -q -D plughw:CARD=Camera -f S16_LE -r 48000 -c 2 -t raw \
              | ${pkgs.pulseaudio}/bin/pacat --playback -d canon-mic --raw --format=s16le --rate=48000 --channels=2 --latency-msec=30
          '';
          serviceConfig = { User = "user"; Restart = "always"; RestartSec = 5; };
        };
        # No GPU in here: Mesa gives software OpenGL, which Zoom, Telegram and
        # Vesktop all need to draw at all.
        hardware.graphics.enable = true;
        programs.nix-ld.enable = true;  # runs the unpacked Zoom binaries
        # Zoom encrypts its saved data with a key tied to the machine ID; a new
        # random one every boot makes it unreadable (and Zoom crashes).
        environment.etc."machine-id".text = "ba3ae33b31131dfda493e8dffb3cd946\n";
        networking.interfaces.sysnet-calls.ipv4.addresses = [ { address = linkAddr "sysnet-calls" "b"; prefixLength = 30; } ];
        networking.defaultGateway = { address = linkAddr "sysnet-calls" "a"; interface = "sysnet-calls"; };
        networking.nameservers = [ "9.9.9.9" ];
      };
    };

    # torrent: qBittorrent behind sys-vpn (Mullvad). Downloads go straight
    # into the host's ~/torrents through a virtiofs share; guest `user` and
    # host arlo are both uid 1000, so the files are yours on the host.
    torrent = {
      autostart = false;
      config = {
        imports = [ (guestBase "torrent" vms.torrent) ];
        microvm = {
          mem = 1024; # MiB
          shares = [ { proto = "virtiofs"; tag = "torrents"; source = "/home/arlo/torrents"; mountPoint = "/home/user/torrents"; } ];
        };
        networking.interfaces.vpn-torrent.ipv4.addresses = [ { address = linkAddr "vpn-torrent" "b"; prefixLength = 30; } ];
        networking.defaultGateway = { address = linkAddr "vpn-torrent" "a"; interface = "vpn-torrent"; };
        networking.nameservers = [ "10.64.0.1" ];
      };
    };
  };
}
