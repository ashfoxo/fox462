#!/usr/bin/env bash
# Deploy this flake to fox-red. Run from anywhere inside the repo on the
# workstation.
#
#   ./deploy.sh             build and switch now
#   ./deploy.sh test        activate, but keep the old generation as boot default
#   ./deploy.sh dry-build   evaluate and show what would be built
#
# The repo is copied to the server and built THERE, rather than built here and
# pushed. Pushing store paths in as arlo would require making arlo a Nix
# trusted user, which is root without the sudo password. Building on the
# server needs only the sudo you already have, and nearly everything comes
# from the binary cache anyway.
#
# DEPLOY_HOST overrides the SSH host (default: fox-red).
set -euo pipefail

host="${DEPLOY_HOST:-fox-red}"
action="${1:-switch}"
remote_dir="/home/arlo/fox-red"

cd "$(git rev-parse --show-toplevel)"

# Whatever reaches the server is a commit you can point back to.
if [ -n "$(git status --porcelain)" ]; then
  echo "deploy.sh: uncommitted changes. Commit first, then deploy." >&2
  exit 1
fi

echo "deploying $(git rev-parse --short HEAD) to $host ($action)"

rsync -a --delete --exclude .git --exclude 'result*' ./ "$host:$remote_dir/"

# path: because the copy has no .git, and root will not read a git repo owned
# by another user anyway. NIX_CONFIG enables flakes for the very first deploy,
# before the config that turns them on permanently is active. Harmless after.
ssh -t "$host" "sudo env NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild $action --flake path:$remote_dir#fox-red"
