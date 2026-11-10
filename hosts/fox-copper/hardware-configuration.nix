# Written before the laptop was ever booted with NixOS (a Dell), so the
# initrd gets a broad set of disk drivers rather than the generated list.
# shortcut: guessed drivers, replace with `nixos-generate-config
# --no-filesystems --show-hardware-config` from the running server when convenient.
{ lib, config, ... }:
{
  # The USB drive it boots from, and the internal one
  boot.initrd.availableKernelModules = [
    "xhci_pci" "ehci_pci" "usb_storage" "uas" "sd_mod" "ahci" "nvme"
  ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
