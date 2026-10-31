{
  # sudo: touch yak-olive OR type password
  security.pam.u2f = {
    control = "sufficient";
    settings.cue = true;   # prints "Please touch the FIDO authenticator."
  };
  security.pam.services.sudo.u2fAuth = true;
  security.sudo.extraConfig = "Defaults timestamp_timeout=0";  # no 5-min cache

  ##### Kernel hardening #####
  boot.kernel.sysctl = {
    # Hostile-LAN routing tricks: ignore ICMP redirects and source routing.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;

    # Local info leaks / attack surface. Side effect: non-root `dmesg` fails.
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;

    # Forensics / live-seizure hardening.
    "kernel.sysrq" = 0;                    # no magic-key tricks at the keyboard
    "kernel.yama.ptrace_scope" = 2;        # only root may ptrace
    "kernel.kexec_load_disabled" = 1;      # no loading a new kernel over this one
    "kernel.perf_event_paranoid" = 3;
    "dev.tty.ldisc_autoload" = 0;
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
  };

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
