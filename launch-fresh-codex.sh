#!/bin/sh
# Launch Codex CLI standalone, without the inference stack.
#
# Builds the agent image from src/codex-stack/Dockerfile on first use and reuses
# it afterwards, so `--fresh` always matches this checkout's Dockerfile and
# toolchain rather than whatever is on the registry. Editing the Dockerfile
# and re-running picks the change up; to force it sooner, run
# `docker rmi code-inference-codex-fresh`.

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
