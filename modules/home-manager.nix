{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  # Pass nixpak input into home-manager modules (apps.nix / webapps.nix)
  home-manager.extraSpecialArgs = { inherit (inputs) nixpak; };
  home-manager.users.arlo = import ../home;

  # Home Manager refuses to replace files it didn't write (an app's own
  # ~/.config/... file, say). With this, the offender is renamed to
  # *.hm-backup and the switch continues.
  home-manager.backupFileExtension = "hm-backup";
}
