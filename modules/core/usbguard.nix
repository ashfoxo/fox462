{
  # Block new USB devices until approved (stops rogue keyboards, storage and
  # other USB attacks on a powered-on machine).
  #
  # Devices already plugged in when the daemon starts are kept, so a boot never
  # locks out the keyboard or fox-blue's USB root disk. Allow a new one for
  # this session with `sudo usbguard list-devices` then
  # `sudo usbguard allow-device <id>`. To keep it across reboots, add a rule
  # below (`sudo usbguard generate-policy` prints the current set).
  services.usbguard = {
    enable = true;
    implicitPolicyTarget = "block";
    presentDevicePolicy = "keep";
    presentControllerPolicy = "keep";
    rules = ''
      allow id 1050:* # YubiKeys: sudo, lock screen, LUKS unlock
    '';
  };
}
