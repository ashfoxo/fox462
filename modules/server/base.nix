# Baseline for a server: firewall, kernel hardening, Nix settings, SSH,
# fail2ban, journald and the everyday tools. What the laptop shares with the
# servers (most sysctls, Nix and garbage collection) is in modules/common.
{ config, lib, ... }:
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

  # The shared sysctls are in common/hardening.nix. Strict reverse-path
  # filtering is server-only: it breaks the laptop's VPN routing.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
  };

  nix.settings.allowed-users = [ "root" "@wheel" ];

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
      LoginGraceTime = 60;  # room for a YubiKey touch; 30 timed out (C11)
      # Who may log in is fox.server.ssh.allowUsers: the host adds its own
      # account, and services that need SSH (Forgejo) add theirs.
      AllowUsers = config.fox.server.ssh.allowUsers;
    };
  };

  security.sudo.execWheelOnly = true;

  # arlo on every server. Its password is in /etc/shadow, set with passwd,
  # and NOT in any backup: a bare-metal restore can't sudo until you reset it
  # from the provider's console. Keys: the YubiKeys below work on every
  # server; each host adds its own Bitwarden key in hosts/<name>/default.nix.
  fox.server.ssh.allowUsers = [ "arlo" ];
  users.users.arlo = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # YubiKeys (touch to log in; ~/.ssh/id_ed25519_sk_*, recoverable from
      # the key itself with `ssh-keygen -K`)
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAwe5WM34JF9GAxeq+4IfAN9ChEegmlgRmliDg/YRpU0AAAAC3NzaDpmb3gtZGVu yak-amber"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIMGPAv8yRUjUKHQiE5HtHfbpYCsbFcGZyLmXmlVjPE6zAAAAC3NzaDpmb3gtZGVu yak-olive"
    ];
  };

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
}
