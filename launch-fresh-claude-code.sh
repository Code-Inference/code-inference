#!/bin/sh
# Launch Claude Code standalone, without the inference stack.
#
# Builds the agent image from src/claude-stack/Dockerfile on first use and reuses
# it afterwards, so `--fresh` always matches this checkout's Dockerfile and
# toolchain rather than whatever is on the registry. Editing the Dockerfile
# and re-running picks the change up; to force it sooner, run
# `docker rmi code-inference-claude-fresh`.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-claude-fresh"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Building $IMAGE from src/claude-stack/Dockerfile (first run)..."
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/src/claude-stack/Dockerfile" "$SCRIPT_DIR"
fi

# --ephemeral and --ephemeral-keep-auth are wrapper flags, consumed here rather
# than forwarded: the first other argument, and everything after it, belongs to
# the agent.
EPHEMERAL=0
KEEP_AUTH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ephemeral)
      EPHEMERAL=1
      shift
      ;;
    --ephemeral-keep-auth)
      KEEP_AUTH=1
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

if [ "$EPHEMERAL" -eq 1 ] && [ "$KEEP_AUTH" -eq 1 ]; then
  echo "Error: --ephemeral and --ephemeral-keep-auth are mutually exclusive." >&2
  exit 2
fi

# claude_home is ~/.claude, where Claude Code keeps its credentials, so it is the
# one volume --ephemeral-keep-auth keeps. --ephemeral keeps no named volume at
# all: the workspace and the read-only ~/.ssh bind remain, everything else lives
# in the container layer and goes away with --rm.
AUTH_VOLUMES='-v claude_home:/home/claude/.claude'
ALL_VOLUMES='-v claude_config:/home/claude/.config/claude
-v claude_data:/home/claude/.local/share/claude
-v claude_state:/home/claude/.local/state/claude
-v claude_cache:/home/claude/.cache/claude
-v claude_home:/home/claude/.claude'

if [ "$EPHEMERAL" -eq 1 ]; then
  VOLUMES=""
elif [ "$KEEP_AUTH" -eq 1 ]; then
  VOLUMES="$AUTH_VOLUMES"
else
  VOLUMES="$ALL_VOLUMES"
fi

# shellcheck disable=SC2086  # $VOLUMES is a literal flag list; no word has a space
exec docker run -it --rm \
  --name claude_fresh \
  -v "$ORIG_PWD:/workspace" \
  $VOLUMES \
  -v "$HOME/.ssh:/home/claude/.ssh:ro" \
  -w /workspace \
  "$IMAGE" \
  "$@"
