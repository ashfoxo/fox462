#!/usr/bin/env bash
# Deploy this flake to a server (fox-red, or any host added later). Run from
# anywhere inside the repo on the workstation.
#
#   ./deploy.sh fox-red             build and switch now
#   ./deploy.sh fox-red test        activate, but keep the old generation as boot default
#   ./deploy.sh fox-red dry-build   evaluate and show what would be built
#
# The repo is copied to the server and built THERE, rather than built here and
# pushed. Pushing store paths in as arlo would require making arlo a Nix
# trusted user, which is root without the sudo password. Building on the
# server needs only the sudo you already have, and nearly everything comes
# from the binary cache anyway.
#
# DEPLOY_HOST overrides the SSH name if it differs from the host name.
set -euo pipefail

name="${1:?usage: ./deploy.sh <host> [switch|test|boot|dry-build]}"
action="${2:-switch}"
host="${DEPLOY_HOST:-$name}"
remote_dir="/home/arlo/$name"

cd "$(git rev-parse --show-toplevel)"

# A switch or boot must be a commit you can point back to. test and
# dry-build may try uncommitted work: test is gone at the next reboot.
if [ -n "$(git status --porcelain)" ]; then
  case "$action" in
    test|dry-build) echo "deploy.sh: deploying UNCOMMITTED changes ($action)" >&2 ;;
    *) echo "deploy.sh: uncommitted changes. Commit first, or use test." >&2; exit 1 ;;
  esac
fi

[ -d "hosts/$name" ] || { echo "deploy.sh: no hosts/$name in this repo." >&2; exit 1; }

echo "deploying $(git rev-parse --short HEAD) to $name via $host ($action)"

rsync -a --delete --exclude .git --exclude 'result*' ./ "$host:$remote_dir/"

# path: because the copy has no .git, and root will not read a git repo owned
# by another user anyway. NIX_CONFIG enables flakes for the very first deploy,
# before the config that turns them on permanently is active. Harmless after.
ssh -t "$host" "sudo env NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild $action --flake path:$remote_dir#$name"
