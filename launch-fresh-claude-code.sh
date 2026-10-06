#!/bin/sh
# Launch Claude Code standalone, without the inference stack.
#
# Image resolution, in order:
#   1. A local code-inference-claude-fresh tag, if one exists -- so a build from this checkout wins
#      over anything on the registry, which matters when working on the stack.
#   2. The published image for this release, pulled from GHCR.
#   3. A local build from src/claude-stack/Dockerfile, if the pull fails.
#
# Step 3 is the fallback for a commit ahead of the latest release: the registry
# has no image for it yet. To force a rebuild after editing the Dockerfile, run
# `docker rmi code-inference-claude-fresh` first.
#
# Volumes are agent-scoped (claude_config / _data / _state / _cache / _home) to match
# the compose stacks, so credentials and settings never collide between agents
# or with opencode's own volumes.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-claude-fresh"
# Published by .github/workflows/publish.yml. Kept in sync with the registry
# path there, which is ghcr.io/<owner>/<repo> with the tag suffixed by agent.
PUBLISHED="ghcr.io/code-inference/code-inference:latest-claude"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Pulling $PUBLISHED..."
  if docker pull "$PUBLISHED"; then
    docker tag "$PUBLISHED" "$IMAGE"
  else
    echo ">>> No published image for this agent; building $IMAGE from src/claude-stack/Dockerfile."
    docker build -t "$IMAGE" -f "$SCRIPT_DIR/src/claude-stack/Dockerfile" "$SCRIPT_DIR"
  fi
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
