# fox-amber's disk layout, for a disaster-recovery reinstall only. NOT
# imported today: the running laptop mounts by UUID from
# hardware-configuration.nix, and that stays until a reinstall.
#
# Matches the current disk: a 512 MB ESP (partlabel EFI) and LUKS
# (partlabel root, opened as cryptroot) holding btrfs @root, @home, @nix
# and @persist.
#
# To reinstall:
#   1. In default.nix, import inputs.disko.nixosModules.disko and ./disko.nix.
#   2. In hardware-configuration.nix, delete the fileSystems and
#      boot.initrd.luks.devices entries (disko generates them), but keep
#      neededForBoot below.
#   3. Boot the NixOS installer on fox-amber, clone the repo, put the
#      passphrase in /tmp/disk.key, then run disko and nixos-install as in
#      hosts/fox-copper/README.md, "Reinstalling" (with .#fox-amber; the
#      secrets key goes to /mnt/persist/var/lib/sops-nix/secrets_ed25519
#      instead of the SSH host key). Then restore /persist and @home from
#      restic and re-enroll the FIDO2 keys (boot.nix).
let
  opts = [ "compress=zstd" "noatime" ];
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          label = "EFI";
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          label = "root";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            passwordFile = "/tmp/disk.key";   # read only while formatting
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = { mountpoint = "/"; mountOptions = opts; };
                "@home" = { mountpoint = "/home"; mountOptions = opts; };
                "@nix" = { mountpoint = "/nix"; mountOptions = opts; };
                "@persist" = { mountpoint = "/persist"; mountOptions = opts; };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
}
