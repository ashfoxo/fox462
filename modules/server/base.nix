# Baseline for a server: firewall, kernel hardening, Nix settings, SSH,
# fail2ban, journald and the everyday tools.
{ config, pkgs, lib, inputs, srv, ... }:
{
  # ntfy-alert.env: NTFY_URL= / NTFY_TOKEN=   (shell-sourceable). How every
  # alert on the server reaches your phone (see helpers.nix).
  fox.server.secretNames = [ "ntfy-alert.env" ];

  time.timeZone = "UTC";

  networking.firewall = let caddy = config.fox.server.caddy; in {
    enable = true;
    allowedTCPPorts = [ 22 ] ++ lib.optionals (caddy.enable && caddy.public) [ 80 443 ];
    # NetBird-only Caddy: HTTPS on the NetBird interface, nothing public.
    interfaces.wt0.allowedTCPPorts = lib.optionals (caddy.enable && !caddy.public) [ 443 ];
  };

  ############################################################################
  # Kernel hardening
  ############################################################################

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.sysrq" = 0;
    "kernel.yama.ptrace_scope" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.tcp_syncookies" = 1;
  };

  nix.settings.allowed-users = [ "root" "@wheel" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  ############################################################################
  # SSH
  ############################################################################

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      MaxAuthTries = 5;
      LoginGraceTime = 30;
      # Who may log in is fox.server.ssh.allowUsers: the host adds its own
      # account, and services that need SSH (Forgejo) add theirs.
      AllowUsers = config.fox.server.ssh.allowUsers;
    };
  };

  security.sudo.execWheelOnly = true;

  ############################################################################
  # fail2ban
  ############################################################################

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
    };
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
      # NetBird peers. The other server's Gatus opens a TCP connection to
      # port 22 every few minutes to check SSH answers, and would get itself
      # banned. Logins are key-only either way.
      "100.64.0.0/10"
    ];
  };

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  # Flakes on the server itself, so deploy.sh can build here.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
