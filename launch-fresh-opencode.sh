#!/bin/sh
# Launch opencode standalone, without the inference stack.
#
# Uses the published upstream image rather than src/opencode-stack/Dockerfile:
# opencode ships and versions that image itself, so there is nothing to build
# here.
#
# The upstream image runs as root with HOME=/root and ships no `opencode` user,
# so HOME and the XDG directories are set explicitly to the paths the named
# volumes mount at. Without them opencode writes to /root, the volumes stay
# empty, and nothing survives the container -- even though --fresh is documented
# as keeping persistent volumes. Verified against 2.0.22: with HOME/XDG set,
# `opencode auth list` creates ~/.config/opencode, ~/.local/share/opencode,
# ~/.local/state/opencode and ~/.cache/opencode under the new HOME itself.
#
# --ephemeral and --ephemeral-keep-auth narrow the volumes the same way they do
# for the other four agents.

set -e

ORIG_PWD="$PWD"

# OPENCODE_VERSION pins the base image. Its releases are tagged v2.0.30 while the
# published image tags omit the `v`, so a leading one is stripped. Unset keeps the
# same default as src/opencode-stack/Dockerfile.
OPENCODE_TAG="${OPENCODE_VERSION:-2.0.22}"
IMAGE="ghcr.io/anomalyco/opencode:${OPENCODE_TAG#v}"

# Consumed here rather than forwarded: the first other argument, and everything
# after it, belongs to the agent.
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

# opencode keeps auth.json in ~/.local/share/opencode, which is opencode_data, so
# that is the one volume --ephemeral-keep-auth keeps. That directory also holds
# session storage, and a named volume cannot be mounted over a single file, so
# opencode's sessions survive too; the other four agents keep credentials and
# history in separate volumes. --ephemeral keeps no named volume at all.
AUTH_VOLUMES='-v opencode_data:/home/opencode/.local/share/opencode'
ALL_VOLUMES='-v opencode_config:/home/opencode/.config/opencode
-v opencode_data:/home/opencode/.local/share/opencode
-v opencode_state:/home/opencode/.local/state/opencode
-v opencode_cache:/home/opencode/.cache/opencode'

if [ "$EPHEMERAL" -eq 1 ]; then
  VOLUMES=""
elif [ "$KEEP_AUTH" -eq 1 ]; then
  VOLUMES="$AUTH_VOLUMES"
else
  VOLUMES="$ALL_VOLUMES"
fi

# shellcheck disable=SC2086  # $VOLUMES is a literal flag list; no word has a space
exec docker run -it --rm \
  --name opencode_fresh \
  -v "$ORIG_PWD:/workspace" \
  $VOLUMES \
  -v "$HOME/.ssh:/home/opencode/.ssh:ro" \
  -e HOME=/home/opencode \
  -e XDG_CONFIG_HOME=/home/opencode/.config \
  -e XDG_DATA_HOME=/home/opencode/.local/share \
  -e XDG_STATE_HOME=/home/opencode/.local/state \
  -e XDG_CACHE_HOME=/home/opencode/.cache \
  -w /workspace \
  "$IMAGE" \
  "$@"
