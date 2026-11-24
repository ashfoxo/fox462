{ ... }:

let
  # Shared with modules/desktop/session.nix and hyprland.nix. Edit
  # lib/session-vars.nix.
  sessionVars = import ../lib/session-vars.nix;
in
{
  imports = [
    ./desktop
  ];

  home.username = "arlo";
  home.homeDirectory = "/home/arlo";

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  services.pass-secret-service = {
    enable = true;
    storePath = "/home/arlo/.password-store";
  };

  programs.bash.enable = true;
  # Context packets for the Tinfoil chat; the tool lives outside the repo.
  programs.bash.shellAliases.ctx = "$HOME/Documents/tinfoil/ctx";

  home.sessionVariables = sessionVars;
}
