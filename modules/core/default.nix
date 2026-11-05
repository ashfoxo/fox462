# Everything every personal machine (laptop, desktop) gets, regardless of
# hardware: Nix itself, the arlo user and its secrets, hardening, time.
{
  imports = [
    ./nix.nix
    ./users.nix
    ./hardening.nix
    ./usbguard.nix
    ./yubikey-removal.nix
  ];

  time.timeZone = "America/New_York";
}
