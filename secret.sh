#!/usr/bin/env bash
# Store a server secret as hosts/<host>/secrets/<name>, encrypted for the keys
# in hosts/<host>/.sops.yaml (your workstation and that server). Nothing is
# written unencrypted.
#
#   ./secret.sh <host> <name>                    asks for one line, typing hidden
#   some-command | ./secret.sh <host> <name>     stores exactly what arrives on stdin
#
# A new secret also needs its name in fox.server.secretNames, in the service
# module that uses it.
#
# To read or change an existing one by hand:
#   cd hosts/<host> && nix shell nixpkgs#sops -c sops edit --input-type binary --output-type binary secrets/<name>
set -euo pipefail

host="${1:?usage: ./secret.sh <host> <name>}"
name="${2:?usage: ./secret.sh <host> <name>}"
cd "$(dirname "$0")/hosts/$host"
mkdir -p secrets

sops="$(nix build --no-link --print-out-paths nixpkgs#sops)/bin/sops"
out="secrets/$name"
trap 'rm -f "$out.tmp"' EXIT

if [ -t 0 ]; then
  IFS= read -rsp "$name (typing hidden): " value
  echo
  printf '%s\n' "$value"
else
  cat
fi | "$sops" --config .sops.yaml encrypt \
       --input-type binary --output-type binary \
       --filename-override "$out" > "$out.tmp"

mv "$out.tmp" "$out"
echo "stored $out"
