# The tools every server has on its PATH. (Directories a service needs are
# made by that service's own file.)
{ config, pkgs, lib, inputs, srv, ... }:
{
  environment.systemPackages = with pkgs; [
    curl
    htop
    git
    cifs-utils
    micro
    tmux
    rsync
    restic
    sqlite
    jq
  ];
}
