#!/bin/sh
# Restart the local inference stack.
#
# Reached via `code-inference --restart`. Understands the same stack flags as
# the launcher (--full-isolation, --disk-name, --privileged), so it restarts
# the stack you actually launch with rather than always the default one.
#
# Volumes are PRESERVED by default. `down` removes containers and networks but
# leaves named volumes alone, which keeps:
#   - opencode auth tokens and config  (opencode_config)
#   - session history                 (opencode_data)
#   - the HuggingFace model cache     (model_hf_data, ~540MB)
#   - training data                   (training_data)
#
# Pass --purge to discard them. That forces a full model re-download and a
# re-login, so it is opt-in and confirms first unless -y is given.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_PWD="$PWD"

NAME_SUFFIX="$(basename "$ORIG_PWD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

cd "$SCRIPT_DIR" || exit 1

usage() {
  cat <<'USAGE'
Usage: code-inference --restart [-y] [--full-isolation] [--disk-name NAME]
                       [--privileged] [--purge]

Restart the inference stack. Pass the same stack flags you launch with.

Options:
  --full-isolation     Restart the per-project stack
    --disk-name NAME   Volumes live on this external disk (default: EXT1TB)
  --privileged         Restart the privileged sandbox stack
                       (requires --full-isolation and --disk-name)
  --purge              Destroy volumes: discards stored auth, session history,
                       training data, and the HuggingFace cache (~540MB
                       re-download)
  -y, --yes            Assume yes; skip the --purge confirmation
  -h, --help           Show this help

Volumes are preserved unless --purge is given.

Examples:
  code-inference --restart
  code-inference --restart --full-isolation --disk-name EXT1TB
  code-inference --restart --full-isolation --privileged --disk-name EXT1TB
USAGE
}

# ── Flag parsing ─────────────────────────────────────────────────────────────
# Mirrors launch-opencode.sh deliberately. That script is on the hot path for
# every launch and is left untouched.
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
DISK_NAME=""
FULL_ISOLATION=0
PRIVILEGED=0
PURGE=0
ASSUME_YES=0

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
    --privileged)
      PRIVILEGED=1
      shift
      ;;
    --purge)
      PURGE=1
      shift
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'." >&2
      echo "Try 'code-inference --restart --help'." >&2
      exit 2
      ;;
  esac
done

# Same constraints as the launcher: --privileged is only safe with an isolated
# stack on a named external disk.
if [ "$PRIVILEGED" -eq 1 ]; then
  if [ "$FULL_ISOLATION" -ne 1 ]; then
    echo "Error: --privileged requires --full-isolation." >&2
    echo "       Try: --restart --full-isolation --privileged --disk-name <disk>" >&2
    exit 2
  fi
  if [ -z "$DISK_NAME" ]; then
    echo "Error: --privileged requires --disk-name." >&2
    echo "       Try: --restart --full-isolation --privileged --disk-name <disk>" >&2
    exit 2
  fi
fi

if [ "$FULL_ISOLATION" -eq 1 ] && [ -n "$DISK_NAME" ]; then
  DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose-full-isolation.yml"
fi

if [ "$PRIVILEGED" -eq 1 ]; then
  PROFILE_NAME="stack_privileged"
else
  PROFILE_NAME="stack"
fi

# ── External-disk bind mounts ────────────────────────────────────────────────
# These are bind mounts (type: none, o: bind), and Docker cannot create a
# missing host path, so the mount fails before the container starts. Create them
# here, as the launcher does. Paths come from the compose file so they cannot
# drift from the volume definitions.
if [ -n "$DISK_NAME" ]; then
  if [ ! -d "/Volumes/${DISK_NAME:-EXT1TB}" ]; then
    echo "Error: external disk '/Volumes/${DISK_NAME:-EXT1TB}' is not mounted." >&2
    exit 1
  fi
  sed -n 's/^[[:space:]]*device:[[:space:]]*"\/Volumes\/[^"]*".*/&/p' \
    "$DOCKER_COMPOSE_FILE" \
    | sed -n 's/.*device:[[:space:]]*"\(.*\)".*/\1/p' \
    | while IFS= read -r device; do
        resolved=$(printf '%s' "$device" \
          | sed "s|\${DISK_NAME:-EXT1TB}|${DISK_NAME:-EXT1TB}|g; s|\${NAME_SUFFIX:-common}|${NAME_SUFFIX:-common}|g")
        if [ ! -d "$resolved" ]; then
          mkdir -p "$resolved"
          echo "  created $resolved"
        fi
      done
fi

# ── Guards ───────────────────────────────────────────────────────────────────
if [ "$PURGE" -eq 1 ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then
    reply="y"
  else
    echo "WARNING: --purge destroys all volumes for project '$NAME_SUFFIX'."
    echo "         This discards stored auth, session history, training data,"
    echo "         and the HuggingFace cache (~540MB re-download)."
    printf "Continue? [y/N]: "
    read -r reply || reply=""
  fi
  case "$reply" in
    y|Y|yes|Yes) ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

# Verify a checkpoint is present before booting, so a missing model fails here
# with a clear message instead of inside the inference container.
#
# Check ORIG_PWD, not the cwd: this script cd's to SCRIPT_DIR so compose
# commands resolve against the install, but models live in the project.
# launch-opencode.sh passes PWD="$ORIG_PWD" to compose for the same reason.
if [ ! -d "$ORIG_PWD/models" ] || [ -z "$(ls -A "$ORIG_PWD/models" 2>/dev/null)" ]; then
  echo "Error: no GGUF checkpoint found in $ORIG_PWD/models." >&2
  echo "       Place one there first. See docs/models/README.md." >&2
  exit 1
fi
echo "Models found in $ORIG_PWD/models:"
ls -lh "$ORIG_PWD/models/"

# ── Restart ──────────────────────────────────────────────────────────────────
PURGE_FLAG=""
[ "$PURGE" -eq 1 ] && PURGE_FLAG="-v"

echo "Stopping stack (project: $NAME_SUFFIX, profile: $PROFILE_NAME)..."
# shellcheck disable=SC2097,SC2098  # assignments apply to the compose process
# shellcheck disable=SC2086  # PURGE_FLAG is an intentional optional word
PWD="$ORIG_PWD" NAME_SUFFIX="$NAME_SUFFIX" DISK_NAME="$DISK_NAME" \
  docker compose -f "$DOCKER_COMPOSE_FILE" -p "$NAME_SUFFIX" \
  --profile "$PROFILE_NAME" down --remove-orphans $PURGE_FLAG

echo "Starting stack..."
# shellcheck disable=SC2097,SC2098  # assignments apply to the compose process
PWD="$ORIG_PWD" NAME_SUFFIX="$NAME_SUFFIX" DISK_NAME="$DISK_NAME" \
  docker compose -f "$DOCKER_COMPOSE_FILE" -p "$NAME_SUFFIX" \
  --profile "$PROFILE_NAME" up --force-recreate --build --remove-orphans -d

echo "Restart complete."