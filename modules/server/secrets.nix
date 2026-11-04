# Secrets for a server. Every name in fox.server.secretNames is the file
# hosts/<hostName>/secrets/<name>, decrypted with the host's SSH host key
# (sops-nix picks it up from services.openssh on its own). Root-only by
# default; a service that needs more sets sops.secrets.<name>.owner and so on.
#
# If the server is ever reinstalled its host key changes: add the new key to
# hosts/<hostName>/.sops.yaml and run `sops updatekeys` on the files before
# the first deploy, or activation fails with "0 successful groups".
{ config, lib, ... }:
{
  sops.secrets = lib.genAttrs config.fox.server.secretNames (name: {
    sopsFile = ../../hosts + "/${config.networking.hostName}/secrets/${name}";
    format = "binary";
  });
}
