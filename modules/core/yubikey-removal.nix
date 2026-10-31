{ pkgs, ... }:

# Pull the YubiKey out and the screen locks at once; if it isn't back within
# 10 seconds the machine powers off. Only counts if a YubiKey has been plugged
# in since boot, so using the machine without your key never triggers it.
# (Panic power-off without a key: Super + Ctrl + Shift + Esc, hypr/binds.lua.)
let
  vendor = "1050";   # Yubico
  systemctl = "${pkgs.systemd}/bin/systemctl";

  onRemove = pkgs.writeShellScript "yubikey-removed" ''
    [ -e /run/yubikey-armed ] || exit 0
    ${pkgs.systemd}/bin/loginctl lock-sessions
    sleep 10
    # Still gone? (Reinserting stops this unit through the udev rule below.)
    for v in /sys/bus/usb/devices/*/idVendor; do
      [ "$(cat "$v" 2>/dev/null)" = "${vendor}" ] && exit 0
    done
    exec ${systemctl} poweroff --force
  '';
in
{
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
      RUN+="${systemctl} --no-block stop yubikey-removed.service"
    ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="${vendor}/*", \
      RUN+="${systemctl} --no-block start yubikey-removed.service"
  '';
}
