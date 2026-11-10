# fox-copper's disk: a 1 GB ESP, the rest LUKS ("cryptcopper") holding btrfs.
# nixos-anywhere wipes and partitions from this; it also generates the
# fileSystems and LUKS entries, so hardware-configuration.nix has none.
# The subvolumes are fox-amber's, so the shared root wipe works the same.
let
  opts = [ "compress=zstd" "noatime" ];
in
{
  disko.devices.disk.main = {
    type = "disk";
    # The Fox drive (SanDisk Extreme, USB), by id so formatting can't hit
    # another disk. The internal disk keeps its Windows install. Wiped on
    # install.
    device = "/dev/disk/by-id/usb-SanDisk_Extreme_55AE_323432364130343030393430-0:0";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          # Unique partlabels: fox-amber's disk uses EFI and root, and disko
          # opens partitions by label, so a shared one could format the wrong
          # disk when installing from fox-amber.
          label = "copper-boot";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          label = "copper-root";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptcopper";   # not cryptroot: see fox.rootWipe.luksName
            # Read only while formatting: nixos-anywhere --disk-encryption-keys
            # puts the passphrase here (README.md, "Installing").
            passwordFile = "/tmp/disk.key";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = { mountpoint = "/"; mountOptions = opts; };
                "@nix" = { mountpoint = "/nix"; mountOptions = opts; };
                "@persist" = { mountpoint = "/persist"; mountOptions = opts; };
              };
            };
          };
        };
      };
    };
  };

  # disko doesn't set this; impermanence needs /persist in the initrd.
  fileSystems."/persist".neededForBoot = true;
}
