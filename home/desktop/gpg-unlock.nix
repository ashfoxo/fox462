{ pkgs, ... }:

# One YubiKey touch at login unlocks GPG (pass, and the app logins
# pass-secret-service serves) for the whole session. The GPG key's passphrase
# is random and nobody types it: it's stored only in ~/.gnupg/passphrase.age,
# encrypted to both YubiKeys (FIDO2, age-plugin-fido2-hmac) and to a recovery
# age key kept in Bitwarden. Any one of the three decrypts it.
#
# Didn't touch in time? `systemctl --user restart gpg-unlock`.
# Recovery without a key: paste the AGE-SECRET-KEY from Bitwarden into a
# file under /run/user/1000 and run
#   age -d -i /run/user/1000/<file> ~/.gnupg/passphrase.age
# then delete the file.
let
  deps = with pkgs; [ age age-plugin-fido2-hmac gnupg gawk libnotify ];

  unlock = pkgs.writeShellScript "gpg-unlock" ''
    export PATH=${pkgs.lib.makeBinPath deps}
    file=$HOME/.gnupg/passphrase.age
    [ -e "$file" ] || exit 0   # not set up yet
    notify-send -a GPG "Touch your YubiKey" "Unlocks pass and app logins for this session"
    pw=$(age -d -j fido2-hmac "$file")
    for grip in $(gpg --with-colons --with-keygrip -K | awk -F: '$1 == "grp" { print $10 }'); do
      printf '%s' "$pw" | ${pkgs.gnupg}/libexec/gpg-preset-passphrase --preset "$grip"
    done
  '';
in
{
  home.packages = with pkgs; [ age age-plugin-fido2-hmac ];  # for setup and recovery

  systemd.user.services.gpg-unlock = {
    Unit = {
      Description = "Unlock GPG with a YubiKey touch";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      # Retries while no key is plugged in, then gives up (see filen.nix).
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = unlock;
      Restart = "on-failure";
      RestartSec = 20;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
