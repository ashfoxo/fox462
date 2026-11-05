# fox-blue: Dad's desktop (ASUS TUF X570-PLUS, Ryzen 9 3900X, RTX 2060
# Super, 32 GB), booted from a portable Samsung T7 Shield. Windows stays on
# the internal drive, untouched; pick the T7 from the F8 boot menu.
{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/personal.nix
    ../../modules/hardware/nvidia.nix
  ];

  networking.hostName = "fox-blue";

  # Booting from USB: never write a boot entry into the motherboard's
  # firmware, so the PC keeps starting Windows by default even with the T7
  # plugged in. systemd-boot still installs the fallback EFI/BOOT/BOOTX64.EFI
  # the F8 menu finds.
  boot.loader.efi.canTouchEfiVariables = false;

  ##### Never sleep #####
  # A desktop that doesn't move, and its whole system is on a USB drive: if
  # the drive drops off the bus during a resume, the running system loses its
  # disk. So no suspend or hibernate at all, automatic or manual. (The
  # laptop's idle suspend lives in modules/hardware/laptop.nix, not imported
  # here.)
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # Lock after 10 minutes, screens off after 15.
  fox.desktop.lockAfter = 600;
  fox.desktop.screenOffAfter = 900;

  ##### Monitors #####
  # Only the ultrawide (DP-2). The 1080p and 1280x1024 screens on DP-1 and
  # HDMI-A-1 stay dark under Hyprland; DP-3 is empty. If a cable moves, check
  # `hyprctl monitors all` and update these. Any screen not named here still
  # lights up through the catch-all rule, so you can't end up with none.
  fox.desktop.monitors = [
    { output = "DP-2"; mode = "3440x1440@59.97"; position = "0x0"; scale = 1; }
    { output = "DP-1"; disabled = true; }
    { output = "HDMI-A-1"; disabled = true; }
  ];

  # The bar and the lock screen's clock and prompt go on the ultrawide, and
  # the bar's prompt reads arlo@fox-blue.
  fox.desktop.barMonitors = [ "DP-2" ];
  fox.desktop.lockMonitor = "DP-2";
  fox.desktop.barHost = "fox-blue";

  ##### Games #####
  # Steam is shared (modules/desktop/programs.nix). gamemode lets games ask
  # for the performance CPU governor while they run: `gamemoderun %command%`
  # in a Steam game's launch options.
  programs.gamemode.enable = true;

  ##### moose-amber #####
  # The 1.4 TB encrypted data partition on the same T7. Unlocked at boot with
  # a key file kept inside the (already unlocked) system partition, so there
  # is still only one passphrase. nofail: a missing key or partition never
  # stops the desktop from booting. The laptop keeps opening it by hand.
  environment.etc.crypttab.text = ''
    moose-amber PARTLABEL=moose-amber /persist/etc/keys/moose-amber.key luks,nofail
  '';
  fileSystems."/home/arlo/moose-amber" = {
    device = "/dev/mapper/moose-amber";
    fsType = "btrfs";
    options = [ "noatime" "nofail" ];
  };

  ##### Backups #####
  # Its own bucket and its own Scaleway API key (fox-blue-s3-* in
  # secrets.yaml).
  fox.backup = {
    enable = true;
    repository = "s3:https://s3.fr-par.scw.cloud/bagger-blue/fox-blue";
    s3SecretPrefix = "fox-blue-";
    # Bulk data, not system state, and big. Leave it to its own backup.
    extraExclude = [ "/home/arlo/moose-amber" ];
  };

  system.stateVersion = "26.05";
}
