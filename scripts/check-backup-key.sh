#!/usr/bin/env bash
# Checks what a host's backup key may do to its Scaleway bucket (AUDIT.md C3).
# Run as root on the host that owns the key:
#
#   laptop:  sudo bash scripts/check-backup-key.sh /run/secrets/rendered/restic-s3-env bagger-amber
#   fox-red: sudo bash check-backup-key.sh /run/secrets/restic-s3-env bagger-red
#
# Every write it tries is a no-op: it writes back the setting it just read, or
# deletes one version of a test object it made itself. The test object stays
# behind as a few bytes under c3-test/ until the 30-day lifecycle removes it.
#
# Wanted: object writes and plain deletes ALLOWED (restic needs them),
# everything else denied.
set -u
env_file=${1:?env file}; bucket=${2:?bucket}
set -a; . "$env_file"; set +a

run() { nix shell nixpkgs#awscli2 -c aws --endpoint-url https://s3.fr-par.scw.cloud --region fr-par "$@"; }
try() {
  local what=$1; shift
  if out=$(run "$@" 2>&1); then echo "ALLOWED  $what"
  else echo "denied   $what  ($(grep -oE '\(([A-Za-z]+)\)' <<<"$out" | head -1))"; fi
}

tmp=$(mktemp); key=c3-test/$(hostname)-$(date +%s)
echo "Fetching the AWS CLI (first run only)..."; run --version >/dev/null 2>&1
echo one > "$tmp"; v1=$(run s3api put-object --bucket "$bucket" --key "$key" --body "$tmp" --query VersionId --output text 2>/dev/null)
echo two > "$tmp"; v2=$(run s3api put-object --bucket "$bucket" --key "$key" --body "$tmp" --query VersionId --output text 2>/dev/null)
rm -f "$tmp"
echo
echo "Bucket $bucket"
echo "  versioning: $(run s3api get-bucket-versioning --bucket "$bucket" --query Status --output text 2>&1 | tail -1)"
echo "  test object versions: ${v1:0:12}… ${v2:0:12}…"
echo

case $v1 in *rror*|"") echo "denied   write an object (restic NEEDS this): $v1" ;; *) echo "ALLOWED  write an object" ;; esac
try "delete an OLD VERSION (must be denied)" s3api delete-object --bucket "$bucket" --key "$key" --version-id "$v1"

pol=$(run s3api get-bucket-policy --bucket "$bucket" --query Policy --output text 2>/dev/null)
if [ -n "$pol" ]; then
  echo "ALLOWED  read the bucket policy"
  try "rewrite the bucket policy (must be denied)" s3api put-bucket-policy --bucket "$bucket" --policy "$pol"
else
  echo "denied   read the bucket policy (can't test changing it)"
fi
try "turn versioning off (must be denied; tried as a no-op Enabled)" \
  s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
lc=$(run s3api get-bucket-lifecycle-configuration --bucket "$bucket" --output json 2>/dev/null)
if [ -n "$lc" ]; then
  echo "ALLOWED  read the lifecycle rule"
  try "change the lifecycle rule (must be denied)" \
    s3api put-bucket-lifecycle-configuration --bucket "$bucket" --lifecycle-configuration "$lc"
else
  echo "denied   read the lifecycle rule (can't test changing it)"
fi
try "list other buckets (should be denied)" s3api list-buckets

try "plain delete of the test object (restic needs this)" s3api delete-object --bucket "$bucket" --key "$key"
