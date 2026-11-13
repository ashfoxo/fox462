# Shared by element-dump.sh / element-apply.sh. Needs MATRIX_TOKEN and MATRIX_HS in the env.
command -v jq >/dev/null || exec nix shell nixpkgs#jq -c "$0" "$@"
: "${MATRIX_TOKEN:?set MATRIX_TOKEN (Element > Settings > Help & About > Advanced)}"
: "${MATRIX_HS:?set MATRIX_HS, e.g. https://matrix.example.org}"
api() { # METHOD PATH [JSON body]; PATH is relative to /_matrix/client/v3
  curl -fsS -X "$1" -H "Authorization: Bearer $MATRIX_TOKEN" -H 'Content-Type: application/json' \
    ${3:+-d "$3"} "$MATRIX_HS/_matrix/client/v3$2"
}
enc() { jq -rn --arg s "$1" '$s|@uri'; }
ME=$(api GET /account/whoami | jq -r .user_id)
