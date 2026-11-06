{ lib, pkgs, inputs, ... }:
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  ##### Boot #####
  # Secure Boot with our own keys: lanzaboote replaces systemd-boot's
  # installer and signs every boot entry, so a swapped kernel or initrd on
  # /boot won't boot. It keeps the systemd-boot settings below (entry limit,
  # no editor) and signs fwupd's firmware-update app too. Keys are created on
  # the first rebuild in /var/lib/sbctl (persisted). One-time firmware steps,
  # and what to do if it won't boot: README.md, "Secure Boot".
  boot.loader.systemd-boot.enable = false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    autoGenerateKeys.enable = true;
  };
  environment.systemPackages = [ pkgs.sbctl ];  # enroll-keys, verify, status

  # A host that boots from a removable drive sets this to false, so installing
  # never writes a boot entry into the machine's firmware.
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.loader.systemd-boot.configurationLimit = 10;
  # No editing the kernel command line from the boot menu.
  boot.loader.systemd-boot.editor = false;

  # Modern systemd initrd. The root wipe lives in
  # boot.initrd.systemd.services.rollback (impermanence.nix).
  # postDeviceCommands is not supported here (the build fails an assertion),
  # so don't reintroduce it.
  boot.initrd.systemd.enable = true;

  # LUKS devices and all fileSystems entries (including /persist with
  # neededForBoot = true) live in each host's hardware-configuration.nix.
  # Don't define boot.initrd.luks.devices.<name>.device here too; that's an
  # eval conflict. The LUKS device must be named "cryptroot" on every host:
  # the rollback script and the options below refer to it by that name.
  #
  # /nix and /persist must be their own subvolumes, not inside @root, or the
  # wipe takes them with it. Check: sudo btrfs subvolume list / && findmnt /nix

  # The generated /boot mount is world-readable (fmask=0022), and systemd-boot's
  # random-seed file lives there; bootctl warns about it. Overridden here
  # rather than editing the generated file, so a regenerate can't undo it.
  fileSystems."/boot".options = lib.mkForce [ "umask=0077" ];

  # TRIM through LUKS (allowDiscards) is off on purpose: it leaks which
  # blocks are in use.

  # FIDO2 unlock: yak-olive (YubiKey Security Key C NFC) = keyslot 0
  # spare key = keyslot 3. Passphrase still works. On a host with no FIDO2
  # key enrolled yet, systemd just asks for the passphrase.
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
    "fido2-device=auto"
    "token-timeout=10s"
  ];
}
