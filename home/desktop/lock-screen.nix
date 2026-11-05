# The one way the session locks (hyprland.nix at login, hypridle for
# everything else). It notes when the lock started: a YubiKey touch only
# unlocks in the first 10 minutes, after that the password is needed
# (modules/desktop/session.nix). A good unlock also clears the password-only
# flag a resume from suspend sets (modules/hardware/laptop.nix).
pkgs: pkgs.writeShellScriptBin "lock-screen" ''
  ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && exit 0
  ${pkgs.coreutils}/bin/date +%s > "$XDG_RUNTIME_DIR/locked-at"
  ${pkgs.hyprlock}/bin/hyprlock && ${pkgs.coreutils}/bin/rm -f "$XDG_RUNTIME_DIR/password-only"
''
