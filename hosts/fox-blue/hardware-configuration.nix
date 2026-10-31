# fox-blue's disk layout, on the Samsung T7 Shield (USB):
#   sda3  NIXBOOT        EFI system partition    -> /boot
#   sda4  fox-blue-luks  LUKS2 "cryptroot", btrfs @root @home @nix @persist
#   sda1, sda2 are moose-share and moose-amber (hosts/fox-blue/default.nix)
#
# Written by hand at install time, then checked against
# `nixos-generate-config --show-hardware-config` run on the desktop.
# Step B1 of README.md checks it against the installed system's
# /etc/nixos copy and replaces it if the UUIDs differ.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # USB (the T7 uses uas), SATA, NVMe and USB keyboards, so the passphrase
  # prompt works on the desktop.
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "uas" "sd_mod" "usbhid" ];
  boot.kernelModules = [ "kvm-amd" ];

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/80bace05-96ae-429e-b986-8dd9886e74f3";

  fileSystems."/" =
    { device = "/dev/mapper/cryptroot"; fsType = "btrfs";
      options = [ "subvol=@root" "compress=zstd" "noatime" ]; };
  fileSystems."/home" =
    { device = "/dev/mapper/cryptroot"; fsType = "btrfs";
      options = [ "subvol=@home" "compress=zstd" "noatime" ]; };
  fileSystems."/nix" =
    { device = "/dev/mapper/cryptroot"; fsType = "btrfs";
      options = [ "subvol=@nix" "compress=zstd" "noatime" ]; };
  fileSystems."/persist" =
    { device = "/dev/mapper/cryptroot"; fsType = "btrfs";
      options = [ "subvol=@persist" "compress=zstd" "noatime" ];
      neededForBoot = true; };
  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/2622-90A3"; fsType = "vfat";
      options = [ "umask=0077" ]; };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = true;
}
