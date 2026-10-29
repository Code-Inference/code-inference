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

# GROK_VERSION pins the installed tool. Unset means the Dockerfile's ARG
# default applies, so nothing is passed and the default stays in one place. A
# pinned run rebuilds every time: the layer cache makes that cheap, and an image
# existing is not evidence that it was built with this version.
BUILD_ARGS=""
if [ -n "${GROK_VERSION:-}" ]; then
  BUILD_ARGS="--build-arg GROK_VERSION=$GROK_VERSION"
fi

if [ -n "$BUILD_ARGS" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Building $IMAGE from src/grok-stack/Dockerfile..."
  # shellcheck disable=SC2086  # BUILD_ARGS is a literal flag list; a version has no spaces
  docker build -t "$IMAGE" $BUILD_ARGS -f "$SCRIPT_DIR/src/grok-stack/Dockerfile" "$SCRIPT_DIR"
fi

# --ephemeral and --ephemeral-keep-auth are wrapper flags, consumed here rather
# than forwarded: the first other argument, and everything after it, belongs to
# the agent.
EPHEMERAL=0
KEEP_AUTH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ephemeral)
      EPHEMERAL=1
      shift
      ;;
    --ephemeral-keep-auth)
      KEEP_AUTH=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ "$EPHEMERAL" -eq 1 ] && [ "$KEEP_AUTH" -eq 1 ]; then
  echo "Error: --ephemeral and --ephemeral-keep-auth are mutually exclusive." >&2
  exit 2
fi

# grok_home is ~/.grok, which holds auth.json and config.toml, so it is the one
# volume --ephemeral-keep-auth keeps. --ephemeral keeps no named volume at all:
# the workspace and the read-only ~/.ssh bind remain, everything else lives in
# the container layer and goes away with --rm.
AUTH_VOLUMES='-v grok_home:/home/grok/.grok'
ALL_VOLUMES='-v grok_config:/home/grok/.config/grok
-v grok_data:/home/grok/.local/share/grok
-v grok_state:/home/grok/.local/state/grok
-v grok_cache:/home/grok/.cache/grok
-v grok_home:/home/grok/.grok'

if [ "$EPHEMERAL" -eq 1 ]; then
  VOLUMES=""
elif [ "$KEEP_AUTH" -eq 1 ]; then
  VOLUMES="$AUTH_VOLUMES"
else
  VOLUMES="$ALL_VOLUMES"
fi

# shellcheck disable=SC2086  # $VOLUMES is a literal flag list; no word has a space
exec docker run -it --rm \
  --name grok_fresh \
  -v "$ORIG_PWD:/workspace" \
  $VOLUMES \
  -v "$HOME/.ssh:/home/grok/.ssh:ro" \
  -w /workspace \
  "$IMAGE" \
  "$@"
