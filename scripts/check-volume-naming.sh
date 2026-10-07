#!/bin/sh
# Check that each agent's Docker volumes carry that agent's own name.
#
# Every agent gets its own config, data, state and cache volumes, so credentials
# and session history for Claude Code are never visible to Cursor. That only
# holds while the volume names keep the agent in them: one `opencode_config`
# copied into docker-compose-claude.yml would silently hand every agent the same
# state, and nothing else in the tree would notice.
#
# Which agent owns a compose file is read from the file name rather than a table
# here, so adding an agent does not mean remembering to update this script:
#
#   docker-compose.yml                        -> opencode
#   docker-compose-claude.yml                 -> claude
#   docker-compose-grok-build-full-isolation.yml -> grok
#   docker-compose-full-isolation.yml         -> opencode
#
# Two invariants are enforced per file:
#
#   1. No volume name mentions another agent. Split on "_" and compare whole
#      components, so `claude_config` is caught in an opencode file while
#      `model_hf_data` -- which mentions no agent -- is not a false positive.
#   2. The agent's own four state volumes are all declared, so a rename cannot
#      quietly drop one.
#
# The inference volumes (model cache, training data) are deliberately
# agent-neutral and shared: five agents must not mean five 540MB downloads.
# They are listed explicitly, so a new shared volume has to be declared here as
# deliberate rather than slipping in unnoticed.
#
# Finally the --fresh launchers are cross-checked against the compose
# declarations, since they mount the same volumes by bare name.

set -e

cd "$(dirname "$0")/.." || exit 1

AGENT_NAMES="opencode claude cursor codex grok"

# Agent-neutral volumes, shared by every agent on purpose.
SHARED_VOLUMES="workspace model_data model_hf_data training_data internal"

# Per-agent state volumes that must exist for every agent.
STATE_SUFFIXES="config data state cache"

status=0

note() {
  printf '%-8s %s\n' "$1" "$2"
  status=1
}

# Nothing to check outside this repository: a project bootstrapped from a
# template gets CI workflows and pre-commit config but no compose files and no
# launcher scripts. With an unmatched glob, a plain `for f in docker-compose*.yml`
# would iterate the literal pattern and fail on a missing file.
# shellcheck disable=SC2086  # deliberate word splitting to test the glob
set -- docker-compose*.yml
if [ ! -e "$1" ]; then
  echo "volume-naming OK: no compose files to check"
  exit 0
fi

# Compose file basename with the docker-compose prefix and .yml suffix removed,
# then any -full-isolation suffix: the compose *base*, which start.sh maps to an
# agent with agent_compose().
compose_base() {
  printf '%s\n' "$1" \
    | sed -e 's/^docker-compose//' -e 's/\.yml$//' -e 's/-full-isolation$//' -e 's/^-//'
}

# Which agent owns a compose file. The base is either empty (the opencode
# stack) or an agent name, possibly with a suffix such as grok-build.
agent_of_compose() {
  base=$(compose_base "$1")
  if [ -z "$base" ]; then
    printf 'opencode\n'
    return
  fi
  for a in $AGENT_NAMES; do
    case "$base" in
      "$a" | "$a"-*) printf '%s\n' "$a"; return ;;
    esac
  done
  printf '\n'
}

# Top-level volume declarations: two-space-indented keys in the trailing
# `volumes:` block. Service-level "- name:/path" mounts are not matched.
declared_volumes() {
  awk '/^volumes:/,0' "$1" | sed -n 's/^  \([A-Za-z_][A-Za-z0-9_]*\):.*/\1/p'
}

for f in docker-compose*.yml; do
  agent=$(agent_of_compose "$f")
  if [ -z "$agent" ]; then
    note UNKNOWN "cannot tell which agent owns $f (base '$(compose_base "$f")')"
    continue
  fi

  for v in $(declared_volumes "$f"); do
    # Whole components only, so claude_config is matched but a hypothetical
    # claudecache is not silently accepted as unrelated.
    foreign=""
    for a in $AGENT_NAMES; do
      [ "$a" = "$agent" ] && continue
      for part in $(printf '%s' "$v" | tr '_' ' '); do
        [ "$part" = "$a" ] && foreign="$a"
      done
    done

    if [ -n "$foreign" ]; then
      note CROSS-AGENT "$f declares '$v', which is ${foreign}'s volume"
      continue
    fi

    case " $v " in
      *" $agent"_* | *" $agent") ;;
      *)
        ok=""
        for s in $SHARED_VOLUMES; do
          [ "$v" = "$s" ] && ok="$s"
        done
        if [ -z "$ok" ]; then
          note UNEXPECTED "$f declares '$v', which is neither ${agent}'s nor a known shared volume"
        fi
        ;;
    esac
  done

  for s in $STATE_SUFFIXES; do
    if ! declared_volumes "$f" | grep -qx "${agent}_${s}"; then
      note MISSING "$f does not declare ${agent}_${s}"
    fi
  done
done

# --fresh launchers mount the same volumes by bare name (no project prefix), so
# each name used there must be one the agent's compose file actually declares.
fresh_launcher_for() {
  case "$1" in
    opencode) echo launch-fresh-opencode.sh ;;
    claude) echo launch-fresh-claude-code.sh ;;
    cursor) echo launch-fresh-cursor.sh ;;
    codex) echo launch-fresh-codex.sh ;;
    grok) echo launch-fresh-grok-build.sh ;;
    *) return 1 ;;
  esac
}

for agent in $AGENT_NAMES; do
  launcher=$(fresh_launcher_for "$agent")
  if [ ! -f "$launcher" ]; then
    note MISSING "no --fresh launcher for $agent (expected $launcher)"
    continue
  fi

  # Named-volume mounts only: "-v <name>:/container/path". The workspace bind
  # mount and ~/.ssh start with a quote or ~ after "-v ", so they do not match,
  # which is what makes this work the same for the multi-line launchers and the
  # one-line launch-fresh-opencode.sh. Uppercase is included deliberately: a name
  # the pattern cannot see is a name this guard can never report.
  used=$(grep -o -- '-v [A-Za-z_][A-Za-z0-9_]*:' "$launcher" | sed 's/^-v //; s/:$//')

  for v in $used; do
    ok=no
    for f in docker-compose*.yml; do
      [ "$(agent_of_compose "$f")" = "$agent" ] || continue
      declared_volumes "$f" | grep -qx "$v" && ok=yes && break
    done
    [ "$ok" = yes ] || note UNDECLARED "$launcher mounts '$v', which no $agent compose file declares"
  done
done

if [ "$status" -eq 0 ]; then
  echo "volume-naming OK: every agent's volumes carry its own name"
fi

exit "$status"