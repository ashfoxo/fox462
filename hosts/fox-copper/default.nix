# fox-copper: a spare laptop at home, the first bare-metal server. Its one
# job is ripping DVDs and encoding them to H.265 (dvd-rip.nix); Jellyfin is on
# fox-red. It is also the test bed for
# disaster recovery: its disk is disko.nix, and the whole install is one
# nixos-anywhere run (README.md).
#
# Unlike the VPSes it has an encrypted disk and a root wiped every boot
# (modules/root-wipe.nix), like fox-amber. After a reboot, unlock the disk
# with a YubiKey at the laptop: README.md, "Unlocking after a reboot".
{ config, inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware-configuration.nix
    ../../modules/server
    ../../modules/root-wipe.nix

    ../../modules/server/services/dvd-rip.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "fox-copper";

  fox.server = {
    caddy.public = false;    # NetBird-only sites, like fox-green
    backup.enable = false;   # nothing to back up yet; set backup.repository when a service lands
  };

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
    editor = false;          # no editing the kernel command line from the boot menu
  };
  # Boots from the Fox USB drive (disko.nix): no boot entry in the
  # laptop's firmware, which also holds the Windows install. systemd-boot
  # still lands at the fallback path the firmware boots from USB.
  boot.loader.efi.canTouchEfiVariables = false;
  boot.initrd.systemd.enable = true;   # the root wipe runs in the systemd initrd
  fox.rootWipe.luksName = "cryptcopper";   # matches disko.nix

  # YubiKey unlock at the keyboard, as on fox-amber (boot.nix): plug it in at
  # boot and touch it. Enrolled with systemd-cryptenroll (README.md); the
  # passphrase still works.
  boot.initrd.luks.devices.cryptcopper.crypttabExtraOpts = [
    "fido2-device=auto"
    "token-timeout=10s"
  ];

  # A server with the lid shut.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  ##### Persistence #####
  # All of /var/lib, not service by service: a service whose state dir was
  # forgotten would lose its data at the next reboot. /etc, /root, /tmp and
  # /var/cache are still wiped.
  environment.persistence."/persist".directories = [ "/var/lib" "/var/log" ];

  # Host keys are read from /persist directly: sops-nix decrypts with this key
  # before impermanence's bind mounts exist. Generated on the workstation
  # before install, so the secrets can be encrypted for it in advance.
  services.openssh.hostKeys = [
    { path = "/persist/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
  ];

  # The other servers keep arlo's password in /etc/shadow (passwd), which the
  # wipe would erase every boot. arlo-password is a yescrypt hash (mkpasswd).
  users.mutableUsers = false;
  fox.server.secretNames = [ "arlo-password" "wifi.env" ];
  sops.secrets.arlo-password.neededForUsers = true;
  users.users.arlo.hashedPasswordFile = config.sops.secrets.arlo-password.path;

  # No SSH unlock: its network is a phone's USB tether, which nothing else
  # can reach. networkd rather than dhcpcd is left from when it had one (the
  # initrd's networkd left stale state that stopped timesyncd); both work.
  networking.useNetworkd = true;

  # Home Wi-Fi. wifi.env holds one line, psk_home=<password>. While the phone
  # is plugged in too, its wired link is preferred (lower route metric).
  networking.wireless = {
    enable = true;
    secretsFile = config.sops.secrets."wifi.env".path;
    networks."Ashkelon_5GHz".pskRaw = "ext:psk_home";
  };
  # The Njalla token only works from fox-green's IPv4 (a NetBird route sends
  # 95.215.19.10 through fox-green-direct). Refuse Njalla over IPv6 so Caddy
  # always falls back to that route, whatever IPv6 the home network has.
  # shortcut: Njalla's API addresses, hard-coded; if they change, renewals fail
  # (fox-red's certOk check warns 10 days ahead).
  networking.firewall.extraCommands = ''
    ip6tables -C OUTPUT -d 2001:67c:2354:2::10 -j REJECT 2>/dev/null \
      || ip6tables -A OUTPUT -d 2001:67c:2354:2::10 -j REJECT
  '';
  networking.firewall.extraStopCommands = ''
    ip6tables -D OUTPUT -d 2001:67c:2354:2::10 -j REJECT 2>/dev/null || true
  '';

  # wpa_supplicant reads the file itself, as its own user.
  sops.secrets."wifi.env".owner = "wpa_supplicant";

  # This server's own Bitwarden key, "fox-copper - main", once you make one
  # (the rest: server/base.nix).
  # users.users.arlo.openssh.authorizedKeys.keys = [ "ssh-ed25519 ..." ];

  # Records the release fox-copper was installed with, not the one it runs.
  system.stateVersion = "26.05";
}
