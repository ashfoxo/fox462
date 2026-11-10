{
  # The wipe itself is in root-wipe.nix (shared with fox-copper); this is
  # what the personal machines keep.
  imports = [ ./root-wipe.nix ];

  ##### Impermanence #####
  # @root is recreated empty every boot. /home/arlo is a tmpfs too
  # (ephemeral-home.nix); the @home subvolume under it is not touched.
  # Wi-Fi networks and Bluetooth pairings are kept (convenience): anyone who
  # unlocks the disk can read the network names and device addresses. Battery
  # history (upower) is left out on purpose: it records when the laptop ran.
  environment.persistence."/persist".directories = [
    "/var/lib/nixos"                   # UID/GID allocations; without it users shift
    "/var/lib/systemd/timers"
    "/var/lib/systemd/backlight"       # brightness
    "/var/lib/systemd/rfkill"          # wifi/bluetooth soft-block state
    "/var/lib/bluetooth"               # paired devices
    "/etc/NetworkManager/system-connections"   # saved Wi-Fi
    "/var/lib/power-profiles-daemon"
    "/var/lib/fwupd"                   # firmware update history
    "/var/lib/sbctl"                   # Secure Boot signing keys (boot.nix)
    "/var/lib/restic-status"           # last successful backup (bar)
    "/var/lib/nixos-update"            # last update result (bar)
    "/etc/mullvad-vpn"
    "/var/cache/mullvad-vpn"
    {
      directory = "/var/lib/netbird-wt0";  # peer identity; owned by the
      user = "netbird-wt0";                # hardened service user, not root
      group = "netbird-wt0";
      mode = "0700";
    }
  ];
}
