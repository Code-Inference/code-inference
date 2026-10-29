#!/bin/sh
# Check that every Dockerfile a compose file builds exists, and that each agent
# build block passes through the version ARG its Dockerfile actually declares.
#
# A compose file can name a Dockerfile that is not in the tree and nothing
# notices until someone runs that agent: `docker compose build` then fails with
# `lstat ...: no such file or directory`. That shipped once, with every grok
# compose file pointing at src/grok-build-stack/ while the stack lived in
# src/grok-stack/. The build args matter for the same reason: an agent version
# variable that compose never forwards is silently ignored, so a pin looks like
# it worked and does nothing.
#
# Invariants, for every `dockerfile:` entry in every docker-compose*.yml:
#   1. The referenced file exists.
#   2. For an agent stack (src/<name>-stack/), the build block passes at least
#      one bare build arg.
#   3. Every bare build arg it passes is declared as an ARG by that Dockerfile,
#      so a copy-paste from another agent (OPENCODE_VERSION in the claude block)
#      is reported instead of quietly overriding nothing.
#
# Bare list entries are required on purpose: compose omits an unset variable
# from a list, so the Dockerfile's ARG default stays the single source of truth.

set -e

cd "$(dirname "$0")/.." || exit 1

status=0

note() {
  printf '%-11s %s\n' "$1" "$2"
  status=1
}

# Nothing to check outside this repository: a project bootstrapped from a
# template gets CI workflows but no compose files.
# shellcheck disable=SC2086  # deliberate word splitting to test the glob
set -- docker-compose*.yml
if [ ! -e "$1" ]; then
  echo "compose-dockerfiles OK: no compose files to check"
  exit 0
fi

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM

# One "path<TAB>arg arg" line per dockerfile: entry, args from the args: block
# that follows it (our convention: immediately after, list form, two-space step).
pairs() {
  awk '
    function flush() {
      if (path != "") printf "%s\t%s\n", path, args
      path = ""; args = ""; inargs = 0
    }
    /^[[:space:]]*dockerfile:[[:space:]]/ {
      flush()
      path = $2
      next
    }
    /^[[:space:]]*args:[[:space:]]*$/ { inargs = 1; next }
    inargs && /^[[:space:]]+-[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/ {
      key = $0
      sub(/^[[:space:]]+-[[:space:]]*/, "", key)
      sub(/[[:space:]]+$/, "", key)
      args = (args == "" ? key : args " " key)
      next
    }
    inargs { inargs = 0 }
    END { flush() }
  ' "$1"
}

tab=$(printf '\t')

for f in docker-compose*.yml; do
  pairs "$f" >"$tmp"
  while IFS="$tab" read -r path args; do
    if [ ! -f "$path" ]; then
      note MISSING "$f builds '$path', which does not exist"
      continue
    fi

    # Only agent stacks carry the version pin; inference and api are shared.
    case "$path" in
      src/*-stack/*) ;;
      *) continue ;;
    esac

    if [ -z "$args" ]; then
      note NO-ARGS "$f builds '$path' with no build args; its version cannot be pinned"
      continue
    fi

    # shellcheck disable=SC2086  # arg names contain no spaces; splitting is the point
    for arg in $args; do
      if ! grep -qE "^ARG[[:space:]]+$arg([=[:space:]]|$)" "$path"; then
        note UNKNOWN-ARG "$f passes '$arg' to '$path', which declares no such ARG"
      fi
    done
  done <"$tmp"
done

if [ "$status" -eq 0 ]; then
  echo "compose-dockerfiles OK: every build path exists and passes its declared version arg"
fi

exit "$status"
