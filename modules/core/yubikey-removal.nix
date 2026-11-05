{ pkgs, ... }:

# Pull the YubiKey out and the screen locks after 1 s; if it isn't back within
# 10 seconds the machine powers off. Only counts if a YubiKey has been plugged
# in since boot, so using the machine without your key never triggers it.
# (Panic power-off without a key: Super + Ctrl + Shift + Esc, hypr/binds.lua.)
#
# Stepping away without powering off: `sudo yubikey-away` turns the power-off
# part off (the screen still locks) until the YubiKey is plugged in again, which
# turns it back on by itself. `sudo yubikey-away cancel` does it by hand.
let
  vendor = "1050";   # Yubico
  systemctl = "${pkgs.systemd}/bin/systemctl";

  onRemove = pkgs.writeShellScript "yubikey-removed" ''
    [ -e /run/yubikey-armed ] || exit 0
    present() {
      for v in /sys/bus/usb/devices/*/idVendor; do
        [ "$(cat "$v" 2>/dev/null)" = "${vendor}" ] && return 0
      done
      return 1
    }
    # A loose plug drops out for a split second; don't lock for that.
    sleep 1
    present && exit 0
    ${pkgs.systemd}/bin/loginctl lock-sessions
    [ -e /run/yubikey-away ] && exit 0
    sleep 9
    [ -e /run/yubikey-away ] && exit 0
    # Still gone? (Reinserting stops this unit through the udev rule below.)
    present && exit 0
    exec ${systemctl} poweroff --force
  '';

  away = pkgs.writeShellScriptBin "yubikey-away" ''
    [ "$(id -u)" = 0 ] || { echo "run it with sudo" >&2; exit 1; }
    case "''${1:-}" in
      cancel) rm -f /run/yubikey-away; echo "power-off on YubiKey removal: ON" ;;
      status) [ -e /run/yubikey-away ] && echo "away: removing the key only locks" \
                                        || echo "armed: removing the key locks, then powers off" ;;
      "")     touch /run/yubikey-away
              echo "away: removing the key only locks, until it is plugged in again" ;;
      *)      echo "usage: sudo yubikey-away [cancel|status]" >&2; exit 1 ;;
    esac
  '';
in
{
  environment.systemPackages = [ away ];

  systemd.services.yubikey-removed = {
    description = "Lock, then power off, after the YubiKey is removed";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = onRemove;
    };
  };

  # PRODUCT is "vendor/product/version" and, unlike ID_VENDOR_ID, is still
  # there when the device is removed.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="${vendor}/*", \
      RUN+="${pkgs.coreutils}/bin/touch /run/yubikey-armed", \
      RUN+="${pkgs.coreutils}/bin/rm -f /run/yubikey-away", \
      RUN+="${systemctl} --no-block stop yubikey-removed.service"
    ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="${vendor}/*", \
      RUN+="${systemctl} --no-block start yubikey-removed.service"
  '';
}
