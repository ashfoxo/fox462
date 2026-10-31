#!/usr/bin/env bash
# Run sops on the personal machines' secrets with the shared secrets key.
#
#   ./sops.sh secrets/secrets.yaml                  edit (micro; re-encrypts on save)
#   ./sops.sh decrypt secrets/secrets.yaml          print decrypted
#   ./sops.sh updatekeys -y secrets/secrets.yaml secrets/phone-ssh-key.enc
#                                                   re-encrypt after editing .sops.yaml
#
# KEY=/path/to/other_ed25519 ./sops.sh ...   uses a different SSH key.
#
# The key is converted with ssh-to-age, because the secrets are encrypted to
# its age form (the age1... keys in .sops.yaml), the same way sops-nix reads
# it at boot. Pointing sops at the SSH key file directly doesn't work for
# those. Runs as root because the key file is root-only.
set -euo pipefail

key="${KEY:-/persist/var/lib/sops-nix/secrets_ed25519}"
cd "$(dirname "$0")"

exec sudo nix shell nixpkgs#sops nixpkgs#ssh-to-age -c sh -c '
  key=$1; shift
  SOPS_AGE_KEY=$(ssh-to-age -private-key -i "$key") EDITOR=${EDITOR:-micro} exec sops "$@"
' sops.sh "$key" "$@"
