#!/bin/sh
# Launch Codex CLI standalone, without the inference stack.
#
# Unlike opencode, Codex CLI has no published container image, so this builds one
# from src/codex-stack/Dockerfile. The build is layer-cached, so it is fast
# when nothing has changed, and only runs at all if the image is missing.
#
# Volumes are agent-scoped (codex_config / _data / _state / _cache / _home) to match
# the compose stacks, so credentials and settings never collide between agents
# or with opencode's own volumes.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-codex-fresh"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Building $IMAGE from src/codex-stack/Dockerfile (first run)..."
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/src/codex-stack/Dockerfile" "$SCRIPT_DIR"
fi

exec docker run -it --rm \
  --name codex_fresh \
  -v "$ORIG_PWD":/workspace \
  -v codex_config:/home/codex/.config/codex \
  -v codex_data:/home/codex/.local/share/codex \
  -v codex_state:/home/codex/.local/state/codex \
  -v codex_cache:/home/codex/.cache/codex \
  -v codex_home:/home/codex/.codex \
  -v ~/.ssh:/home/codex/.ssh:ro \
  -w /workspace \
  "$IMAGE" \
  "$@"
