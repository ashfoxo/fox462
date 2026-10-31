# Single source of truth for session environment variables.
#
# This is a plain attrset, not a module. It is `import`ed by:
#   - modules/desktop/session.nix -> environment.sessionVariables (TTY / PAM logins)
#   - home/default.nix            -> home.sessionVariables (bash)
#   - home/desktop/hyprland.nix   -> Hyprland `env` (with $HOME expanded to a real path)
#
# Change a value here and all three places follow.
{
  SSH_AUTH_SOCK = "$HOME/.bitwarden-ssh-agent.sock";

  # Electron apps (incl. bitwarden-desktop) use the Secret Service, which
  # services.pass-secret-service provides from ~/.password-store.
  ELECTRON_EXTRA_LAUNCH_ARGS = "--password-store=gnome-libsecret";

  # Deliberately no ELECTRON_OZONE_PLATFORM_HINT. Forcing "x11" globally put
  # every Electron app on one shared XWayland server, where they can observe
  # each other's input. If a single app misbehaves under native Wayland, scope
  # the workaround to it with an xdg.desktopEntries override (exec =
  # "... --ozone-platform=x11 %U"), and never with --no-sandbox.
}
