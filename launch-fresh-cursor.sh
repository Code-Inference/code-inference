#!/bin/sh
# Launch Cursor CLI standalone, without the inference stack.
#
# Unlike opencode, Cursor CLI has no published container image, so this builds one
# from src/cursor-stack/Dockerfile. The build is layer-cached, so it is fast
# when nothing has changed, and only runs at all if the image is missing.
#
# Volumes are agent-scoped (cursor_config / _data / _state / _cache / _home) to match
# the compose stacks, so credentials and settings never collide between agents
# or with opencode's own volumes.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-cursor-fresh"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Building $IMAGE from src/cursor-stack/Dockerfile (first run)..."
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/src/cursor-stack/Dockerfile" "$SCRIPT_DIR"
fi

exec docker run -it --rm \
  --name cursor_fresh \
  -v "$ORIG_PWD":/workspace \
  -v cursor_config:/home/cursor/.config/cursor-agent \
  -v cursor_data:/home/cursor/.local/share/cursor-agent \
  -v cursor_state:/home/cursor/.local/state/cursor-agent \
  -v cursor_cache:/home/cursor/.cache/cursor-agent \
  -v cursor_home:/home/cursor/.cursor-agent \
  -v ~/.ssh:/home/cursor/.ssh:ro \
  -w /workspace \
  "$IMAGE" \
  "$@"
