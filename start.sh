#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Agents this wrapper can launch. Each maps to its own launcher script, compose
# file, template folder, user, home and volumes, so credentials, session history
# and settings never collide between agents.
AGENT_NAMES="opencode, claude, cursor, codex, grok"

# Agent used when --agent is omitted, in every mode: plain launch, --fresh,
# --full-isolation and --restart. Stated here rather than left to fall out of
# the code below, so the default is readable and cannot change silently.
# opencode is the default because it is the only agent with a published image --
# the others build locally on first run.
DEFAULT_AGENT="opencode"

# ── Agent mapping ────────────────────────────────────────────────────────────
# Single source of truth for agent name -> launcher and compose file. Every mode
# resolves through here, so adding an agent cannot leave one mode behind.

# Reject an unknown or empty agent name. Called directly, not in a subshell, so
# the exit stops the script.
validate_agent() {
  case "$1" in
    opencode | claude | cursor | codex | grok) return 0 ;;
  esac
  if [ -z "$1" ]; then
    echo "Error: --agent requires a value." >&2
  else
    echo "Error: unknown agent '$1'." >&2
  fi
  echo "       One of: ${AGENT_NAMES}" >&2
  exit 2
}

# Compose file basename (no extension) for the agent's stack.
agent_compose() {
  case "$1" in
    opencode) echo "docker-compose" ;;
    claude)   echo "docker-compose-claude" ;;
    cursor)   echo "docker-compose-cursor" ;;
    codex)    echo "docker-compose-codex" ;;
    grok)     echo "docker-compose-grok-build" ;;
    *) return 1 ;;
  esac
}

# Launcher script names: launch-<stack>.sh and launch-fresh-<fresh>.sh
agent_launcher() {
  case "$1" in
    opencode) echo "launch-opencode.sh" ;;
    claude)   echo "launch-claude-code.sh" ;;
    cursor)   echo "launch-cursor.sh" ;;
    codex)    echo "launch-codex.sh" ;;
    grok)     echo "launch-grok-build.sh" ;;
    *) return 1 ;;
  esac
}

agent_fresh_launcher() {
  case "$1" in
    opencode) echo "launch-fresh-opencode.sh" ;;
    claude)   echo "launch-fresh-claude-code.sh" ;;
    cursor)   echo "launch-fresh-cursor.sh" ;;
    codex)    echo "launch-fresh-codex.sh" ;;
    grok)     echo "launch-fresh-grok-build.sh" ;;
    *) return 1 ;;
  esac
}

# Folder of per-agent project templates: templates/<agent>-default
agent_template_dir() {
  case "$1" in
    opencode) echo "templates/opencode-default" ;;
    claude)   echo "templates/claude-default" ;;
    cursor)   echo "templates/cursor-default" ;;
    codex)    echo "templates/codex-default" ;;
    grok)     echo "templates/grok-default" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<EOF
Usage: code-inference [--agent NAME] [mode] [options] [-- agent-args]

--agent must be the first argument, so which agent is in play is never in
doubt. Omit it and ${DEFAULT_AGENT} is used.

Modes (at most one; defaults to a plain launch):
  --fresh              Run the agent standalone, without the inference stack,
                       on persistent named volumes
  --restart            Restart the inference stack (volumes preserved)
                       Accepts --full-isolation, --disk-name, --privileged, --purge
  --full-isolation     Run via compose with a scoped project name and
                       per-project volumes

Options:
  --agent NAME         Run a coding agent instead of ${DEFAULT_AGENT}.
                       Must be first. One of: ${AGENT_NAMES}
                       Default: ${DEFAULT_AGENT}
    --disk-name NAME   Use an external disk for volumes (default: EXT1TB)
  --privileged         Run with docker.sock + privileged + root, so it can spawn
                       nested containers. The container is the sandbox boundary;
                       the host stays protected. Requires --full-isolation and
                       --disk-name. Trusted workspaces only.
  --help, -h           Show this help

Examples:
  code-inference                                   # opencode, with inference
  code-inference --agent claude                    # Claude Code, with inference
  code-inference --agent claude --fresh            # Claude Code, standalone
  code-inference --agent codex --full-isolation --disk-name EXT1TB
  code-inference --agent cursor --restart

Options also accept the --name=value form: --agent=claude, --disk-name=EXT1TB.
Anything after -- is passed to the agent. An unrecognised flag is an error
rather than being ignored, so a typo cannot silently run a different agent at a
different privilege level.
Each agent gets its own user, home, volumes and project templates, so
credentials, session history and settings never collide between agents.
EOF
}

# ── Flag parsing ─────────────────────────────────────────────────────────────
# --agent is positional: it must be the first argument. Anything else would let
# the agent and the mode disagree, so a misplaced --agent is an error rather
# than being silently ignored. Everything after -- or the first unrecognised
# argument goes to the agent.
AGENT="$DEFAULT_AGENT"

# Check the whole flag vocabulary up front, without consuming anything.
#
# The loops below stop at the first argument they do not recognise and forward
# the remainder to the launcher, which repeats the trick. So a single
# unrecognised flag used to swallow every wrapper flag after it -- including
# --privileged and --disk-name -- and hand them to the agent instead. A typo
# silently ran the wrong agent at the wrong privilege level; only the agent's
# own "Unrecognized flag" error gave it away.
#
#   code-inference --claude --full-isolation --disk-name EXT1TB --privileged
#     -> ran opencode, non-privileged, and passed all four flags to it
#
# Validating rather than consuming is deliberate: --disk-name needs its value
# left in place for the launcher, so the flags stay in "$@" untouched and only
# the vocabulary is checked. Flags meant for the agent go after --.
validate_options() {
  for arg in "$@"; do
    case "$arg" in
      --) return 0 ;; # everything past -- belongs to the agent
      --agent=* | --disk-name=*) continue ;;
      -*)
        case "$arg" in
          --fresh | --restart | --full-isolation | --agent | --help | -h) continue ;;
          # Parsed by the launcher and restart.sh, which start.sh dispatches to.
          --disk-name | --privileged | --purge) continue ;;
          *)
            echo "Error: unknown option '$arg'." >&2
            echo "       Flags for the agent go after --." >&2
            echo "       Try 'code-inference --help'." >&2
            exit 2
            ;;
        esac
        ;;
    esac
  done
}

validate_options "$@"

case "${1:-}" in
  --agent)
    if [ -z "${2:-}" ]; then
      echo "Error: --agent requires a value." >&2
      echo "       One of: ${AGENT_NAMES}" >&2
      exit 2
    fi
    validate_agent "$2"
    AGENT="$2"
    shift 2
    ;;
  # --agent=NAME is accepted alongside --agent NAME. Missing it silently ran
  # opencode, since the unrecognised --agent was forwarded to the agent.
  --agent=*)
    validate_agent "${1#--agent=}"
    AGENT="${1#--agent=}"
    shift
    ;;
esac

FRESH=0
RESTART=0
FULL_ISOLATION=0
HELP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --fresh)
      FRESH=1
      shift
      ;;
    --restart)
      RESTART=1
      shift
      ;;
    --full-isolation)
      FULL_ISOLATION=1
      shift
      ;;
    --agent | --agent=*)
      echo "Error: --agent must be the first argument." >&2
      echo "       It selects the agent and its project templates, so it cannot" >&2
      echo "       follow a mode flag and still be unambiguous." >&2
      echo "       Try: code-inference --agent NAME $*" >&2
      exit 2
      ;;
    --help | -h)
      HELP=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ "$HELP" -eq 1 ]; then
  usage
  exit 0
fi

# --fresh and --restart are two different things: a standalone agent versus a
# stack restart. Reject the combination rather than silently honouring one.
if [ "$FRESH" -eq 1 ] && [ "$RESTART" -eq 1 ]; then
  echo "Error: --fresh and --restart are mutually exclusive." >&2
  echo "       --fresh runs the agent alone; --restart restarts the stack." >&2
  exit 2
fi

[ -n "$AGENT" ] || AGENT="$DEFAULT_AGENT"
validate_agent "$AGENT"

# ── Project config bootstrap ─────────────────────────────────────────────────
# Each agent has its own template folder, because the instruction file and its
# path differ per agent (CLAUDE.md, AGENTS.md, .cursor/rules/*.mdc, ...) while
# the shared project files do not. Only meaningful for a plain or isolated
# launch: --fresh and --restart do not start the agent in this workspace.
# Finder and Finder-adjacent tools create "<name> 2.md" duplicates when a folder
# is copied on macOS. One was committed into templates/ and offered to every new
# project as a project template. .gitignore covers ._* and .DS_Store, but no
# safe pattern can ignore "name 2.md" without risking a real file, so drop it
# here instead: a " 2" name is only a duplicate if the de-duplicated original
# exists alongside it.
is_finder_duplicate() {
  base="$1"
  case "$base" in
    *.*) stem="${base%.*}"; ext=".${base##*.}" ;;
    *) stem="$base"; ext="" ;;
  esac
  case "$stem" in
    *" 2" | *" 3" | *" 4" | *" 5" | *" 6" | *" 7" | *" 8" | *" 9") ;;
    *) return 1 ;;
  esac
  [ -f "$TEMPLATE_DIR/${stem% *}$ext" ]
}

describe_template_file() {
  case "$1" in
    AGENTS.md | CLAUDE.md) echo "instructions: conventions, commands" ;;
    *git-workflow*) echo "git workflow rules: branching, PRs, tags, sync" ;;
    opencode.json) echo "provider config: models, instructions, provider URL" ;;
    .pre-commit-config.yaml) echo "pre-commit hooks: whitespace, YAML, large files" ;;
    dev-requirements.txt) echo "dev dependencies: pre-commit, linters, type checkers" ;;
    .github/workflows/*) echo "CI/CD: lint, test, auto-PR, release workflows" ;;
    *) echo "project template" ;;
  esac
}

# Never scaffold the checkout that provides the templates. Running start.sh from
# inside the code-inference repo is a mistake, not a project to seed: every file
# it offers already exists here, and if one were missing it would add a template
# copy to the repo itself. Only files that are absent are ever created, so this
# cannot overwrite anything -- but it can still pollute the repo.
CWD_PHYSICAL="$(pwd -P)"
SCRIPT_PHYSICAL="$(cd "$SCRIPT_DIR" && pwd -P)"
INSIDE_TEMPLATES_REPO=0
[ "$CWD_PHYSICAL" = "$SCRIPT_PHYSICAL" ] && INSIDE_TEMPLATES_REPO=1

if [ "$FRESH" -ne 1 ] && [ "$RESTART" -ne 1 ] && [ "$INSIDE_TEMPLATES_REPO" -eq 0 ]; then
  TEMPLATE_DIR="$SCRIPT_DIR/$(agent_template_dir "$AGENT")"

  # The file list is read from the template folder rather than hardcoded, so a
  # new agent or a new template file is offered automatically and cannot drift
  # from what actually ships.
  #
  # From git when possible: only committed files are templates. Using `find`
  # offered anything lying on disk, and a Finder duplicate ("AGENTS 2.md",
  # created when a folder is copied on macOS) got committed once and was then
  # offered to every new project as a project template.
  if git -C "$TEMPLATE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    TEMPLATE_FILES="$(cd "$TEMPLATE_DIR" && git ls-files)"
  else
    # No git (vendored copy): fall back to find, minus the artefacts.
    TEMPLATE_FILES="$(cd "$TEMPLATE_DIR" && find . -type f \
      ! -name '.DS_Store' ! -name '._*' ! -name '*~' ! -name '*.icloud' \
      | sed 's|^\./||' | sort)"
  fi

  MISSING=""
  OLD_IFS="$IFS"
  IFS='
'
  # shellcheck disable=SC2086  # word splitting on newline is the point here
  for f in $TEMPLATE_FILES; do
    is_finder_duplicate "$f" && continue
    if [ ! -f "./$f" ]; then
      MISSING="$MISSING  - $(printf '%-44s' "$f") ($(describe_template_file "$f"))\n"
    fi
  done
  IFS="$OLD_IFS"

  if [ -n "$MISSING" ]; then
    echo "Missing config files in $(pwd) for agent '$AGENT':"
    printf '%b' "$MISSING"
    printf 'Create from %s? [Y/n]: ' "$(agent_template_dir "$AGENT")"
    read -r REPLY || true
    case "$REPLY" in
      n | N | no | No) echo "Skipping." ;;
      *)
        OLD_IFS="$IFS"
        IFS='
'
        # shellcheck disable=SC2086
        for f in $TEMPLATE_FILES; do
          is_finder_duplicate "$f" && continue
          [ -f "./$f" ] && continue
          mkdir -p "./$(dirname "$f")"
          cp "$TEMPLATE_DIR/$f" "./$f"
          echo "Created $(pwd)/$f"
        done
        IFS="$OLD_IFS"
        echo "Customize as needed."
        ;;
    esac
  fi
fi

# ── Dispatch ─────────────────────────────────────────────────────────────────
# The agent is resolved up front, so every mode below honours --agent and
# DEFAULT_AGENT rather than only the mode that happens to match the first
# argument.
if [ "$FRESH" -eq 1 ]; then
  exec "$SCRIPT_DIR/$(agent_fresh_launcher "$AGENT")" "$@"
fi

if [ "$RESTART" -eq 1 ]; then
  # restart.sh selects the agent's compose file from the basename passed here, so
  # the agent mapping stays in this script rather than being duplicated.
  #
  # --full-isolation has to be passed on explicitly: the loop above consumed it,
  # so restart.sh never saw it and its "FULL_ISOLATION && DISK_NAME" test was
  # always false. --restart --full-isolation silently restarted the shared,
  # non-isolated stack instead of the project's own.
  RESTART_ISOLATION=""
  [ "$FULL_ISOLATION" -eq 1 ] && RESTART_ISOLATION="--full-isolation"
  # shellcheck disable=SC2086  # empty-or-one-word expansion is the point
  exec "$SCRIPT_DIR/restart.sh" --compose "$(agent_compose "$AGENT")" \
    $RESTART_ISOLATION "$@"
fi

if [ "$FULL_ISOLATION" -eq 1 ]; then
  exec "$SCRIPT_DIR/$(agent_launcher "$AGENT")" --full-isolation "$@"
fi

exec "$SCRIPT_DIR/$(agent_launcher "$AGENT")" "$@"