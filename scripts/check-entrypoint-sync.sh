#!/bin/sh
# Check that the two entrypoint copies have not silently drifted.
#
# src/common/entrypoint.sh is shared by the claude, codex, cursor and grok
# stacks. src/opencode-stack/entrypoint.sh is the pre-split copy, kept so the
# opencode image keeps building exactly as before. Duplication is temporary, but
# two copies of the same bootstrap logic drift the moment someone fixes a bug in
# only one of them -- and the opencode container would then behave differently
# from every other stack with no error anywhere.
#
# Two differences are expected and allowed:
#   1. the header comment, which explains each file's role
#   2. the final exec: `exec opencode "$@"` versus
#      `exec "${AGENT_BIN:-opencode}" "$@"`, which run the same command when
#      AGENT_BIN is unset, as it is in the opencode stack
#
# Anything else is drift and fails.

set -e

cd "$(dirname "$0")/.." || exit 1

COMMON="src/common/entrypoint.sh"
LEGACY="src/opencode-stack/entrypoint.sh"

for f in "$COMMON" "$LEGACY"; do
  if [ ! -f "$f" ]; then
    echo "MISSING  $f"
    exit 1
  fi
done

tmp_common="$(mktemp)"
tmp_legacy="$(mktemp)"
trap 'rm -f "$tmp_common" "$tmp_legacy"' EXIT

# Drop comment lines (the headers intentionally differ) and reduce both exec
# forms to one canonical line, so only real logic differences remain.
normalize() {
  sed -e '/^[[:space:]]*#/d' \
      -e '/^exec .*opencode.* "\$@"$/s|.*|exec opencode "$@"|' \
      "$1" > "$2"
}

normalize "$COMMON" "$tmp_common"
normalize "$LEGACY" "$tmp_legacy"

if cmp -s "$tmp_common" "$tmp_legacy"; then
  echo "entrypoint-sync OK: shared logic identical across both entrypoint copies"
  exit 0
fi

echo "DRIFT    $COMMON and $LEGACY differ beyond the header and exec line:"
echo "--- $LEGACY"
echo "+++ $COMMON"
diff -u "$tmp_legacy" "$tmp_common" || true

exit 1