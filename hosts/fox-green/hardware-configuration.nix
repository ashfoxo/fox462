# Generated on fox-green with nixos-generate-config --show-hardware-config,
# plus where GRUB goes and the zram swap the install came with.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # BIOS boot; vda1 is the small partition GRUB uses, vda2 is root.
  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/5ca2f36c-8d61-43b9-91ef-f91556d462b8";
    fsType = "ext4";
  };

  swapDevices = [ ];
  # Swap in compressed RAM: builds on a 2 GB server need the headroom.
  zramSwap.enable = true;
}
