#!/bin/sh
# Launch Grok Build standalone, without the inference stack.
#
# Image resolution, in order:
#   1. A local code-inference-grok-fresh tag, if one exists -- so a build from this checkout wins
#      over anything on the registry, which matters when working on the stack.
#   2. The published image for this release, pulled from GHCR.
#   3. A local build from src/grok-stack/Dockerfile, if the pull fails.
#
# Step 3 is the fallback for a commit ahead of the latest release: the registry
# has no image for it yet. To force a rebuild after editing the Dockerfile, run
# `docker rmi code-inference-grok-fresh` first.
#
# Volumes are agent-scoped (grok_config / _data / _state / _cache / _home) to match
# the compose stacks, so credentials and settings never collide between agents
# or with opencode's own volumes.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-grok-fresh"
# Published by .github/workflows/publish.yml. Kept in sync with the registry
# path there, which is ghcr.io/<owner>/<repo> with the tag suffixed by agent.
PUBLISHED="ghcr.io/code-inference/code-inference:latest-grok"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Pulling $PUBLISHED..."
  if docker pull "$PUBLISHED"; then
    docker tag "$PUBLISHED" "$IMAGE"
  else
    echo ">>> No published image for this agent; building $IMAGE from src/grok-stack/Dockerfile."
    docker build -t "$IMAGE" -f "$SCRIPT_DIR/src/grok-stack/Dockerfile" "$SCRIPT_DIR"
  fi
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
