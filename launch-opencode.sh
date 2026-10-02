#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ORIG_PWD="$PWD"

NAME_SUFFIX="$(basename "$ORIG_PWD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

cd "$SCRIPT_DIR" || exit 1

if [ "$1" = "--full-isolation" ]; then
  shift
  if [ "$1" = "--disk-name" ] && [ -n "${2:-}" ]; then
    DISK_NAME="${2}"
    DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose-full-isolation.yml"
    shift 2
  else
    echo "No --disk-name specified for --full-isolation. Using main disk isolated compose stack."
    DISK_NAME=""
    DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
  fi
  # shellcheck disable=SC2097,SC2098
  PWD="$ORIG_PWD" NAME_SUFFIX="$NAME_SUFFIX" DISK_NAME="$DISK_NAME" exec docker compose -f "$DOCKER_COMPOSE_FILE" -p "$NAME_SUFFIX" --profile stack run --rm --name "opencode-$NAME_SUFFIX" --build --remove-orphans opencode "$@"
else
  PWD="$ORIG_PWD" exec docker compose --profile stack run --rm --name "opencode-$NAME_SUFFIX" --build --remove-orphans opencode "$@"
fi
