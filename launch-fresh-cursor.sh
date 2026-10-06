#!/bin/sh
# Launch Cursor CLI standalone, without the inference stack.
#
# Builds the agent image from src/cursor-stack/Dockerfile on first use and reuses
# it afterwards, so `--fresh` always matches this checkout's Dockerfile and
# toolchain rather than whatever is on the registry. Editing the Dockerfile
# and re-running picks the change up; to force it sooner, run
# `docker rmi code-inference-cursor-fresh`.

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
