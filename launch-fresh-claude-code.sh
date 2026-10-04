#!/bin/sh
# Launch Claude Code standalone, without the inference stack.
#
# Unlike opencode, Claude Code has no published container image, so this builds one
# from src/claude-stack/Dockerfile. The build is layer-cached, so it is fast
# when nothing has changed, and only runs at all if the image is missing.
#
# Volumes are agent-scoped (claude_config / _data / _state / _cache / _home) to match
# the compose stacks, so credentials and settings never collide between agents
# or with opencode's own volumes.

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
  -v "$ORIG_PWD":/workspace \
  -v claude_config:/home/claude/.config/claude \
  -v claude_data:/home/claude/.local/share/claude \
  -v claude_state:/home/claude/.local/state/claude \
  -v claude_cache:/home/claude/.cache/claude \
  -v claude_home:/home/claude/.claude \
  -v ~/.ssh:/home/claude/.ssh:ro \
  -w /workspace \
  "$IMAGE" \
  "$@"
