#!/bin/sh
# Check that the files every project template shares are byte-identical across
# all templates/<agent>-default folders and the templates/workspace scaffold.
#
# The templates are separate folders on purpose: each agent needs its own
# instruction file at its own path (CLAUDE.md, AGENTS.md, .cursor/rules/*.mdc).
# The rest -- git workflow, pre-commit, dev requirements, CI workflows -- is
# agent-neutral and must not drift, or two agents would end up working from
# different rules in the same repository.
#
# Skills are not templates any more: `--add-skills` installs them from upstream,
# so the repository carries no copies to keep in sync.
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
  for d in templates/*-default templates/workspace; do
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
    echo "DRIFT    $f differs between templates:"
    for d in templates/*-default templates/workspace; do
      [ -f "$d/$f" ] || continue
      printf '           %-30s %s\n' "$d" "$(cksum <"$d/$f")"
    done
    status=1
  fi
done

# The workspace scaffold ships one instruction text under both names, because it
# is used with any agent. The bootstrap offers only the name the agent reads, so
# the two must stay identical or switching agent would change the rules.
if ! cmp -s templates/workspace/AGENTS.md templates/workspace/CLAUDE.md; then
  echo "DRIFT    templates/workspace/CLAUDE.md differs from templates/workspace/AGENTS.md"
  status=1
fi

# templates/workspace/.gitignore is live inside this repository: it ignores every
# root subdirectory and re-includes the scaffold. A scaffold directory without a
# matching !/ line would be silently untracked, so flag it here instead of
# letting it disappear from git status. Skills installed later are covered by the
# same negations.
for d in templates/workspace/* templates/workspace/.[!.]*; do
  [ -d "$d" ] || continue
  if git check-ignore -q "$d"; then
    echo "IGNORED  $d (add a !/ line for it to templates/workspace/.gitignore)"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "template-sync OK: shared files identical, workspace scaffold consistent"
fi

exit "$status"
