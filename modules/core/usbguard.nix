{
  # Block new USB devices until approved (stops rogue keyboards, storage and
  # other USB attacks on a powered-on machine).
  #
  # Devices already plugged in when the daemon starts are kept, so a boot never
  # locks out the keyboard or a USB root disk. Allow a new one for
  # this session with `sudo usbguard list-devices` then
  # `sudo usbguard allow-device <id>`. To keep it across reboots, add its line
  # from `usbguard generate-policy` below, minus via-port and parent-hash so
  # it works in any port.
  #
  # hash is a fingerprint of the device's descriptors, not a secret: a
  # programmable device can copy it, and devices without a serial match every
  # unit of the same model. What it does pin is the interface list, so a fake
  # "YubiKey" or "T7" can't also be a keyboard.
  services.usbguard = {
    enable = true;
    implicitPolicyTarget = "block";
    presentDevicePolicy = "keep";
    presentControllerPolicy = "keep";
    rules = ''
      # Built in
      allow id 1d6b:0002 serial "0000:00:14.0" name "xHCI Host Controller" hash "jEP/6WzviqdJ5VSeTUY8PatCNBKeaREvo2OqdplND/o=" with-interface 09:00:00
      allow id 1d6b:0003 serial "0000:00:14.0" name "xHCI Host Controller" hash "E8Zs26CP5+JQoiPVmDSuTb4j11VatW+WHlWxiX8+qJc=" with-interface 09:00:00
      allow id 0c45:6a09 serial "" name "Integrated_Webcam_HD" hash "VX1bQxS9SF2Lv0EfFrCnBzQGfjfYagybcRg1v4AP29U=" with-interface { 0e:01:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 0e:02:00 }
      allow id 8087:0026 serial "" name "" hash "Z5csNGxiUukPPZwSHPyUqpVCNagsfOSSNL2CfXhw4IY=" with-interface { e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 }

      # Security Key C NFC, firmware 5.7.1 (both keys; FIDO only, no serial
      # over USB, so any key of this model and firmware matches)
      allow id 1050:0402 serial "" name "YubiKey FIDO" hash "UMsy7mj8IUBMmPL/oDO7vLJgKcUQiHlyZnqiOZPbKlA=" with-interface 03:00:00

      # Input
      allow id 1ea7:0064 serial "" name "2.4G Mouse" hash "nCMm/ymO0jVjDVqJjR6/qW7O6K8P8T8DftAjC0+we0s=" with-interface 03:01:02
      allow id 413c:2105 serial "" name "Dell USB Keyboard" hash "wqROqDHTqC75UkiKSyBDwVpJWESb5wGrSNY6N0VRTSs=" with-interface 03:01:01

      # Storage
      allow id 04e8:61fb serial "S6NRNS0XA18467X" name "PSSD T7 Shield" hash "+sLq4q77LEUVmR/to3kM/X3i+hg969yaRZnhrHecfMI=" with-interface { 08:06:50 08:06:62 }
    '';
  };
}
