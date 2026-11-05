# What every machine gets, personal (core/) and server (server/) alike.
{
  imports = [
    ./hardening.nix
    ./nix.nix
    ./netbird.nix
  ];
}
