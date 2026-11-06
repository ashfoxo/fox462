{
  # sudo: yak-olive's PIN plus a touch, OR type password. The key is worn all
  # the time, so a touch alone would give root to whoever has you and the laptop.
  security.pam.u2f = {
    control = "sufficient";
    settings.cue = true;   # prints "Please touch the FIDO authenticator."
  };
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.sudo.rules.auth.u2f.settings.pinverification = 1;
  security.sudo.extraConfig = "Defaults timestamp_timeout=0";  # no 5-min cache

  # No text logins on Ctrl+Alt+F2..F6, so nobody at the locked laptop can guess
  # passwords there. Root keeps its password for emergency mode.
  services.logind.settings.Login = { NAutoVTs = 0; ReserveVT = 0; };

  ##### Kernel hardening #####
  # The sysctls are shared with the servers: common/hardening.nix.

  # No kernel modules load once boot is done, so root can't slip one in.
  # Anything needed later must load at boot: these are what Mullvad, NetBird,
  # Bluetooth, the Filen drive and USB drives, audio and tethering use after
  # login. A device that stops working when plugged in later needs its module
  # here (dmesg says "module loading disabled"); pick an older generation at
  # boot to get back in meanwhile.
  security.lockKernelModules = true;
  boot.kernelModules = [
    "nf_tables" "nft_ct" "nft_fib_ipv4" "nft_fib_ipv6" "nft_masq" "nft_nat"
    "nft_chain_nat" "nft_reject_inet" "nft_compat" "xt_conntrack" "xt_pkttype"
    "xt_tcpudp" "wireguard" "tun"
    "bnep" "rfcomm" "hidp"
    "fuse" "usb_storage" "uas" "exfat" "ext4"
    "snd_usb_audio" "cdc_ether" "cdc_ncm" "rndis_host"
  ];

  # Wipe memory on allocation and free, so freed secrets don't linger in RAM
  # for a cold-boot or live-memory read.
  boot.kernelParams = [
    "init_on_alloc=1"
    "init_on_free=1"
    "slab_nomerge"
    "page_alloc.shuffle=1"
    "vsyscall=none"
    "debugfs=off"
  ];

  # FireWire and Thunderbolt are DMA paths into RAM and nothing here uses them
  # (the laptop's USB-C port only charges and carries plain USB data).
  boot.blacklistedKernelModules = [ "firewire-core" "firewire-ohci" "thunderbolt" ];

  # Logs live in RAM only and vanish at power-off (nothing under /var/log is
  # persisted; see impermanence.nix).
  services.journald.extraConfig = "Storage=volatile";

  # /tmp in RAM, so scratch files never touch the disk.
  boot.tmp.useTmpfs = true;

  # Disables coredump storage completely to protect secrets in memory upon process crashes.
  systemd.coredump.settings.Coredump = {
    Storage = "none";
    ProcessSizeMax = 0;
  };
}
