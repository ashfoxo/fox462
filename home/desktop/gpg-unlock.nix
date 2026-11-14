{ pkgs, ... }:

# One YubiKey touch right after you pass the lock screen (lock-screen.nix
# starts this service) unlocks GPG (pass, and the app logins
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
    set -e
    export PATH=${pkgs.lib.makeBinPath deps}
    # Already unlocked (a later re-lock): no touch needed. A real decrypt test,
    # because the agent says "cached" even when a failed touch preset an empty
    # passphrase. (Not signing: that fails with this passphrase, cause unknown.)
    echo x | gpg --batch --default-recipient-self -e 2>/dev/null | gpg --batch --pinentry-mode error -d >/dev/null 2>&1 && exit 0
    gpg-connect-agent reloadagent /bye >/dev/null   # drop any bad preset
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
  };
}
