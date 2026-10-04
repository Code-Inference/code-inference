#!/bin/sh
# Launch Grok Build standalone, without the inference stack.
#
# Unlike opencode, Grok Build has no published container image, so this builds one
# from src/grok-stack/Dockerfile. The build is layer-cached, so it is fast
# when nothing has changed, and only runs at all if the image is missing.
#
# Volumes are agent-scoped (grok_config / _data / _state / _cache / _home) to match
# the compose stacks, so credentials and settings never collide between agents
# or with opencode's own volumes.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-grok-fresh"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Building $IMAGE from src/grok-stack/Dockerfile (first run)..."
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/src/grok-stack/Dockerfile" "$SCRIPT_DIR"
fi

exec docker run -it --rm \
  --name grok_fresh \
  -v "$ORIG_PWD":/workspace \
  -v grok_config:/home/grok/.config/grok \
  -v grok_data:/home/grok/.local/share/grok \
  -v grok_state:/home/grok/.local/state/grok \
  -v grok_cache:/home/grok/.cache/grok \
  -v grok_home:/home/grok/.grok \
  -v ~/.ssh:/home/grok/.ssh:ro \
  -w /workspace \
  "$IMAGE" \
  "$@"
