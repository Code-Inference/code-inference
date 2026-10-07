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

exec docker run -it --rm \
  --name claude_fresh \
  -v "$ORIG_PWD:/workspace" \
  -v claude_config:/home/claude/.config/claude \
  -v claude_data:/home/claude/.local/share/claude \
  -v claude_state:/home/claude/.local/state/claude \
  -v claude_cache:/home/claude/.cache/claude \
  -v claude_home:/home/claude/.claude \
  -v ~/.ssh:/home/claude/.ssh:ro \
  -w /workspace \
  "$IMAGE" \
  "$@"
