#!/bin/sh
# Check that the files every agent template shares are byte-identical across all
# templates/<agent>-default folders.
#
# The templates are separate folders on purpose: each agent needs its own
# instruction file at its own path (CLAUDE.md, AGENTS.md, .cursor/rules/*.mdc).
# The rest -- git workflow, pre-commit, dev requirements, CI workflows -- is
# agent-neutral and must not drift, or two agents would end up working from
# different rules in the same repository.
#
# Files unique to one agent (opencode.json, CLAUDE.md, .cursor/rules/*.mdc) are
# ignored: they are meant to differ.

set -e

cd "$(dirname "$0")/.." || exit 1

SHARED="docs/git-workflow.md
.pre-commit-config.yaml
dev-requirements.txt
.github/workflows/ci.yml
.github/workflows/main-pr-source.yml
.github/workflows/open-pr-to-development.yml
.github/workflows/publish.yml"

status=0

# shellcheck disable=SC2086  # SHARED is a newline-separated list, split on purpose
for f in $SHARED; do
  missing=""
  # One "checksum bytes" line per template, joined by |. cksum prints two
  # fields, so each result is kept as a single unit rather than word-split.
  hashes=""
  for d in templates/*-default; do
    if [ ! -f "$d/$f" ]; then
      missing="$missing $d"
      continue
    fi
    hashes="$hashes$(cksum <"$d/$f")
|"
  done

  if [ -n "$missing" ]; then
    echo "MISSING  $f absent from:$missing"
    status=1
  fi

  # Drift when the templates do not all share one checksum. A single distinct
  # value means every copy is identical, which is the passing case.
  distinct=$(printf '%s' "$hashes" | tr '|' '\n' | sort -u | grep -c . || true)
  if [ "$distinct" -gt 1 ]; then
    echo "DRIFT    $f differs between agent templates:"
    for d in templates/*-default; do
      [ -f "$d/$f" ] || continue
      printf '           %-30s %s\n' "$d" "$(cksum <"$d/$f")"
    done
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "template-sync OK: shared files identical across all agent templates"
fi

exit "$status"