{ config, ... }:
{
  # Passwords come from sops-nix, fully declarative.
  sops.defaultSopsFile = ../../secrets/secrets.yaml;

  # One key for every personal machine's secrets: an ed25519 key made just
  # for this, kept in Bitwarden and copied to the same path on each machine
  # (root-only, no passphrase: nobody is there to type one at boot). Its
  # public half is the age key in .sops.yaml.
  #
  # neededForUsers secrets are decrypted very early in activation, possibly
  # before impermanence's bind mounts exist, so the key is read straight from
  # /persist. sops-nix skips a listed key that is missing or has a
  # passphrase, so a host can list extra keys safely.
  sops.age.sshKeyPaths = [ "/persist/var/lib/sops-nix/secrets_ed25519" ];

  sops.secrets.arlo-password = {
    neededForUsers = true;
  };
  sops.secrets.root-password = {
    neededForUsers = true;
  };

  users.mutableUsers = false;
  users.users.arlo.hashedPasswordFile = config.sops.secrets.arlo-password.path;
  users.users.root.hashedPasswordFile = config.sops.secrets.root-password.path;

  ##### Users #####
  users.users.arlo = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "dialout" "video" "cdrom" "netbird-wt0" ];
  };
}
