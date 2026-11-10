# The root wipe, shared by every host with impermanence (fox-amber,
# fox-copper): @root is recreated empty every boot, and only what a host lists
# under environment.persistence."/persist" survives. Each host lists its own.
#
# Needs: the systemd initrd (boot.initrd.systemd.enable), a LUKS device named
# fox.rootWipe.luksName holding btrfs subvolumes @root and @persist, and
# /persist with neededForBoot = true.
{ config, inputs, lib, pkgs, ... }:
let
  luks = config.fox.rootWipe.luksName;
in
{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  # A host can rename it so it never clashes with the machine installing it:
  # with two opened LUKS devices of one name, disko could format the wrong one.
  options.fox.rootWipe.luksName = lib.mkOption {
    type = lib.types.str;
    default = "cryptroot";
    description = "Name of the opened LUKS device holding the btrfs root.";
  };

  config = {
    # Tools the rollback script calls. The systemd initrd already ships bash,
    # coreutils and the filesystem tools (btrfs-progs comes from your btrfs
    # filesystems); findutils is the one it does not, and the script needs `find`.
    boot.initrd.systemd.initrdBin = with pkgs; [ btrfs-progs findutils ];

    environment.persistence."/persist" = {
      hideMounts = true;
      files = [ "/etc/machine-id" ];
    };

    # Root wipe (systemd stage 1): move @root into old_roots, delete snapshots
    # older than a day (a safety net, not an archive), create a fresh empty
    # @root. The recursive delete exists because @root has nested subvolumes
    # (srv, tmp, var/tmp, var/lib/machines, var/lib/portables).
    # -mindepth 1 keeps find from returning old_roots itself.
    boot.initrd.systemd.services.rollback = {
      description = "Rollback BTRFS root subvolume to a pristine state";
      wantedBy = [ "initrd.target" ];
      # After LUKS is unlocked, before the root filesystem is mounted.
      after = [ "systemd-cryptsetup@${luks}.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /mnt
        mount -o subvol=/ /dev/mapper/${luks} /mnt
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

        for i in $(find /mnt/old_roots/ -mindepth 1 -maxdepth 1 -mtime +0); do
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
  };
}
