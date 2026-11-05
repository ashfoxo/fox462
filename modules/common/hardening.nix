# Kernel hardening every machine gets, personal and server. What only one
# side needs stays there: memory wiping and DMA blocking in core/hardening.nix,
# strict reverse-path filtering in server/base.nix (it breaks the laptop's
# VPN routing).
{
  boot.kernel.sysctl = {
    # Hostile-network routing tricks: ignore ICMP redirects and source routing.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.tcp_syncookies" = 1;

    # Local info leaks and attack surface. Side effect: non-root `dmesg` fails.
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.perf_event_paranoid" = 3;
    "dev.tty.ldisc_autoload" = 0;

    # Against someone with a session or at the keyboard.
    "kernel.sysrq" = 0;                    # no magic-key tricks
    "kernel.yama.ptrace_scope" = 2;        # only root may ptrace
    "kernel.kexec_load_disabled" = 1;      # no loading a new kernel over this one
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
  };
}
