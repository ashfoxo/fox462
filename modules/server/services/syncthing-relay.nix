# A private Syncthing relay, so fox-grey (a Windows PC that can't join
# NetBird) can reach fox-red's Syncthing. fox-grey registers here and
# waits; fox-red dials it through here (lib/syncthing.nix).
#
# Private: it joins no public pool, and only a device that knows the token
# may register. The token is only checked when a device registers, never
# when one dials, so it lives here and on fox-grey only, never in the
# Syncthing configs in this repo. Everything relayed is end-to-end TLS
# between the two devices, so the relay never sees file contents.
#
# Its ID (the relay:// URI's ?id=) is its certificate, made on first start
# in /var/lib/private/syncthing-relay. A rebuild from scratch makes a new
# one: put it in lib/syncthing.nix (fox-grey's relay) and on fox-grey.
# journalctl -u syncthing-relay prints the URI at start.
{ config, pkgs, ... }:
{
  # syncthing-relay-token: a random string, e.g.
  #   openssl rand -hex 32 | ./secret.sh fox-green syncthing-relay-token
  fox.server.secretNames = [ "syncthing-relay-token" ];

  systemd.services.syncthing-relay = {
    description = "Syncthing relay (private, for fox-grey)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # Not the NixOS module: it can only take the token as a plain option,
    # which would put it in the Nix store. It's still on the command line
    # here (strelaysrv has no other way), visible to local users in ps.
    script = ''
      exec ${pkgs.syncthing-relay}/bin/strelaysrv \
        -keys="$STATE_DIRECTORY" \
        -listen=:22067 \
        -status-srv= \
        -global-rate=10000000 \
        -token="$(<"$CREDENTIALS_DIRECTORY/token")"
    '';
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "syncthing-relay";
      LoadCredential = "token:${config.sops.secrets.syncthing-relay-token.path}";
      Restart = "on-failure";
      CapabilityBoundingSet = "";
      MemoryMax = "256M";   # a 2 GB server that also runs the exit nodes
    };
  };

  # Public: fox-grey isn't on NetBird. 10 MB/s in total (-global-rate above).
  networking.firewall.allowedTCPPorts = [ 22067 ];
}
