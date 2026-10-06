#!/bin/sh
# Launch Grok Build standalone, without the inference stack.
#
# Builds the agent image from src/grok-stack/Dockerfile on first use and reuses
# it afterwards, so `--fresh` always matches this checkout's Dockerfile and
# toolchain rather than whatever is on the registry. Editing the Dockerfile
# and re-running picks the change up; to force it sooner, run
# `docker rmi code-inference-grok-fresh`.

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
