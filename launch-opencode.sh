#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

NAME_SUFFIX="$(basename "$ORIG_PWD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

cd "$SCRIPT_DIR" || exit 1

# Parse launcher flags. Order-independent; unrecognised args pass to opencode.
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
DISK_NAME=""
FULL_ISOLATION=0
PRIVILEGED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --full-isolation)
      FULL_ISOLATION=1
      shift
      ;;
    --disk-name)
      if [ -z "${2:-}" ]; then
        echo "Error: --disk-name requires a value." >&2
        exit 2
      fi
      DISK_NAME="$2"
      shift 2
      ;;
    --disk-name=*)
      if [ -z "${1#--disk-name=}" ]; then
        echo "Error: --disk-name requires a value." >&2
        exit 2
      fi
      DISK_NAME="${1#--disk-name=}"
      shift
      ;;
    --privileged)
      PRIVILEGED=1
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

# --privileged runs a container with host-equivalent access (docker.sock,
# privileged: true, root). The container is the sandbox boundary, so the mode
# is only safe when the stack is also isolated from other projects.
if [ "$PRIVILEGED" -eq 1 ]; then
  if [ "$FULL_ISOLATION" -ne 1 ]; then
    echo "Error: --privileged requires --full-isolation." >&2
    echo "       It grants host-equivalent access, so it is only offered with" >&2
    echo "       an isolated stack that cannot collide with other projects." >&2
    echo "       Try: --full-isolation --privileged --disk-name <disk>" >&2
    exit 2
  fi
  # Without --disk-name this falls back to the local compose file, which shares
  # ${PWD} and the default volume root with every other project.
  if [ -z "$DISK_NAME" ]; then
    echo "Error: --privileged requires --disk-name." >&2
    echo "       Without it the stack falls back to local volumes shared with" >&2
    echo "       other projects. Try: --full-isolation --privileged --disk-name <disk>" >&2
    exit 2
  fi
fi

if [ "$FULL_ISOLATION" -eq 1 ] && [ -n "$DISK_NAME" ]; then
  DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose-full-isolation.yml"
fi

if [ "$PRIVILEGED" -eq 1 ]; then
  PROFILE_NAME="stack_privileged"
  SERVICE_NAME="opencode_privileged"
else
  PROFILE_NAME="stack"
  SERVICE_NAME="opencode"
fi

# External-disk volumes are bind mounts (type: none, o: bind). Docker cannot
# create a host path for a bind mount, so a missing directory fails the mount
# before the container starts. The Dockerfile mkdir covers only in-container XDG
# dirs, so this must happen host-side. Paths are read from the compose file so
# they cannot drift from the volume definitions.
ensure_bind_mount_dirs() {
  if [ ! -d "/Volumes/${DISK_NAME:-EXT1TB}" ]; then
    echo "Error: external disk '/Volumes/${DISK_NAME:-EXT1TB}' is not mounted." >&2
    echo "       Mount it, or drop --disk-name to use local volumes." >&2
    return 1
  fi

  sed -n 's/^[[:space:]]*device:[[:space:]]*"\/Volumes\/[^"]*".*/&/p' "$DOCKER_COMPOSE_FILE" \
    | sed -n 's/.*device:[[:space:]]*"\(.*\)".*/\1/p' \
    | while IFS= read -r device; do
        resolved=$(printf '%s' "$device" \
          | sed "s|\${DISK_NAME:-EXT1TB}|${DISK_NAME:-EXT1TB}|g; s|\${NAME_SUFFIX:-common}|${NAME_SUFFIX:-common}|g")
        if [ ! -d "$resolved" ]; then
          mkdir -p "$resolved" || return 1
          echo "  created $resolved"
        fi
      done
}

if [ -n "$DISK_NAME" ]; then
  ensure_bind_mount_dirs || exit 1
fi

if [ "$PRIVILEGED" -eq 1 ]; then
  echo "Using privileged compose stack with disk name: $DISK_NAME"
  echo "  Grants host-equivalent access (docker.sock + privileged + root)."
  echo "  Only use this on trusted workspaces."
elif [ "$FULL_ISOLATION" -eq 1 ]; then
  if [ -n "$DISK_NAME" ]; then
    echo "Using non-privileged compose stack with disk name: $DISK_NAME"
  else
    echo "No --disk-name specified for --full-isolation. Using main disk isolated compose stack."
  fi
fi

# shellcheck disable=SC2097,SC2098
PWD="$ORIG_PWD" NAME_SUFFIX="$NAME_SUFFIX" DISK_NAME="$DISK_NAME" exec docker compose \
  -f "$DOCKER_COMPOSE_FILE" -p "$NAME_SUFFIX" \
  --profile "$PROFILE_NAME" \
  run --rm --name "opencode-$NAME_SUFFIX" --build --remove-orphans \
  "$SERVICE_NAME" "$@"
