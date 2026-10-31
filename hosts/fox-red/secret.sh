#!/usr/bin/env bash
# Store a secret as secrets/<name>, encrypted for the keys listed in
# .sops.yaml (your workstation and fox-red). Nothing is written unencrypted.
#
#   ./secret.sh <name>                    asks for one line, typing hidden
#   some-command | ./secret.sh <name>     stores exactly what arrives on stdin
#
# A new secret also needs its name added to secretNames in configuration.nix.
#
# To read or change an existing one by hand:
#   nix shell nixpkgs#sops -c sops edit --input-type binary --output-type binary secrets/<name>
set -euo pipefail

name="${1:?usage: ./secret.sh <name>}"
cd "$(dirname "$0")"
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
