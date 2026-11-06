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
    # Only a key usbguard allowed counts: a blocked fake "Yubico" device still
    # shows up in sysfs, with authorized = 0.
    present() {
      for d in /sys/bus/usb/devices/*; do
        [ "$(cat "$d/idVendor" 2>/dev/null)" = "${vendor}" ] &&
          [ "$(cat "$d/authorized" 2>/dev/null)" = 1 ] && return 0
      done
      return 1
    }
    # A loose plug drops out for a split second; don't lock for that.
    sleep 1
    present && exit 0
    ${pkgs.systemd}/bin/loginctl lock-sessions
    for _ in 1 2 3 4 5 6 7 8 9; do
      sleep 1
      [ -e /run/yubikey-away ] && exit 0
      present && exit 0
    done
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
      RUN+="${pkgs.coreutils}/bin/rm -f /run/yubikey-away"
    ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="${vendor}/*", \
      RUN+="${systemctl} --no-block start yubikey-removed.service"
  '';
}
