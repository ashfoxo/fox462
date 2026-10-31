{ pkgs, ... }:
{
  # Tools the rollback script calls. The systemd initrd already ships bash,
  # coreutils and the filesystem tools (btrfs-progs comes from your btrfs
  # filesystems); findutils is the one it does not, and the script needs `find`.
  boot.initrd.systemd.initrdBin = with pkgs; [ btrfs-progs findutils ];

  ##### Impermanence #####
  # @root is recreated empty every boot. /home/arlo is a tmpfs too
  # (ephemeral-home.nix); the @home subvolume under it is not touched.
  # Wi-Fi networks and Bluetooth pairings are kept (convenience): anyone who
  # unlocks the disk can read the network names and device addresses. Battery
  # history (upower) is left out on purpose: it records when the laptop ran.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"                   # UID/GID allocations; without it users shift
      "/var/lib/systemd/timers"
      "/var/lib/systemd/backlight"       # brightness
      "/var/lib/systemd/rfkill"          # wifi/bluetooth soft-block state
      "/var/lib/bluetooth"               # paired devices
      "/etc/NetworkManager/system-connections"   # saved Wi-Fi
      "/var/lib/power-profiles-daemon"
      "/var/lib/fwupd"                   # firmware update history
      "/var/lib/restic-status"           # last successful backup (lock screen)
      "/etc/mullvad-vpn"
      "/var/cache/mullvad-vpn"
      {
        directory = "/var/lib/netbird-wt0";  # peer identity; owned by the
        user = "netbird-wt0";                # hardened service user, not root
        group = "netbird-wt0";
        mode = "0700";
      }
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # Root wipe (systemd stage 1): move @root into old_roots, delete snapshots
  # older than 7 days, create a fresh empty @root. The recursive delete exists
  # because @root has nested subvolumes (srv, tmp, var/tmp, var/lib/machines,
  # var/lib/portables). -mindepth 1 keeps find from returning old_roots itself.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    # After LUKS is unlocked, before the root filesystem is mounted.
    after = [ "systemd-cryptsetup@cryptroot.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt
      mount -o subvol=/ /dev/mapper/cryptroot /mnt
      mkdir -p /mnt/old_roots

      if [[ -e /mnt/@root ]]; then
        timestamp=$(date --date="@$(stat -c %Y /mnt/@root)" "+%Y-%m-%d_%H:%M:%S")
        mv /mnt/@root "/mnt/old_roots/$timestamp"
      fi

      delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
          delete_subvolume_recursively "/mnt/$i"
        done
        btrfs subvolume delete "$1"
      }

      for i in $(find /mnt/old_roots/ -mindepth 1 -maxdepth 1 -mtime +7); do
        delete_subvolume_recursively "$i"
      done

      btrfs subvolume create /mnt/@root
      umount /mnt
    '';
  };

  # Detect bit rot on the one filesystem that holds everything.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };
}
