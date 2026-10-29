#!/bin/sh
# Launch Hermes Agent standalone, without the inference stack.
#
# Builds the agent image from src/hermes-stack/Dockerfile on first use and reuses
# it afterwards, so `--fresh` always matches this checkout's Dockerfile and
# toolchain rather than whatever is on the registry. Editing the Dockerfile
# and re-running picks the change up; to force it sooner, run
# `docker rmi code-inference-hermes-fresh`.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

IMAGE="code-inference-hermes-fresh"

# HERMES_VERSION pins the installed tool. Unset means the Dockerfile's ARG
# default applies, so nothing is passed and the default stays in one place. A
# pinned run rebuilds every time: the layer cache makes that cheap, and an image
# existing is not evidence that it was built with this version.
BUILD_ARGS=""
if [ -n "${HERMES_VERSION:-}" ]; then
  BUILD_ARGS="--build-arg HERMES_VERSION=$HERMES_VERSION"
fi

if [ -n "$BUILD_ARGS" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">>> Building $IMAGE from src/hermes-stack/Dockerfile..."
  # shellcheck disable=SC2086  # BUILD_ARGS is a literal flag list; a version has no spaces
  docker build -t "$IMAGE" $BUILD_ARGS -f "$SCRIPT_DIR/src/hermes-stack/Dockerfile" "$SCRIPT_DIR"
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

# hermes_home is ~/.hermes, where Hermes Agent keeps auth.json, so it is the one volume
# --ephemeral-keep-auth keeps. --ephemeral keeps no named volume at all: the
# workspace and the read-only ~/.ssh bind remain, everything else lives in the
# container layer and goes away with --rm.
AUTH_VOLUMES='-v hermes_home:/home/hermes/.hermes'
ALL_VOLUMES='-v hermes_config:/home/hermes/.config/hermes
-v hermes_data:/home/hermes/.local/share/hermes
-v hermes_state:/home/hermes/.local/state/hermes
-v hermes_cache:/home/hermes/.cache/hermes
-v hermes_home:/home/hermes/.hermes'

if [ "$EPHEMERAL" -eq 1 ]; then
  VOLUMES=""
elif [ "$KEEP_AUTH" -eq 1 ]; then
  VOLUMES="$AUTH_VOLUMES"
else
  VOLUMES="$ALL_VOLUMES"
fi

# shellcheck disable=SC2086  # $VOLUMES is a literal flag list; no word has a space
exec docker run -it --rm \
  --name hermes_fresh \
  -v "$ORIG_PWD:/workspace" \
  $VOLUMES \
  -v "$HOME/.ssh:/home/hermes/.ssh:ro" \
  -w /workspace \
  "$IMAGE" \
  "$@"
