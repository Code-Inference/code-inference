#!/bin/sh
set -e

REPO_URL="https://github.com/Code-Inference/code-inference.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.code-inference}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
CMD_NAME="${CMD_NAME:-code-inference}"

echo "==> Installing code-inference to $INSTALL_DIR"

# Check prerequisites
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: 'docker' not found. Please install Docker first."
  exit 1
fi

# Clone or update repo
if [ -d "$INSTALL_DIR" ]; then
  echo "==> Updating existing installation..."
  cd "$INSTALL_DIR" && git pull
else
  echo "==> Cloning repo..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Create wrapper script in BIN_DIR
WRAPPER="$BIN_DIR/$CMD_NAME"
WRAPPER_CONTENT='#!/bin/sh
exec "'"$INSTALL_DIR"'/start.sh" "$@"
'

if ! mkdir -p "$BIN_DIR" 2>/dev/null; then
  echo "==> Installing with sudo..."
  sudo mkdir -p "$BIN_DIR"
  echo "$WRAPPER_CONTENT" | sudo tee "$WRAPPER" >/dev/null
  sudo chmod +x "$WRAPPER"
else
  echo "$WRAPPER_CONTENT" > "$WRAPPER"
  chmod +x "$WRAPPER"
fi

echo "==> Installed! Run '$CMD_NAME' from any project directory."
echo "    '$CMD_NAME' runs opencode; '$CMD_NAME --agent claude' runs another agent."
echo "    Use '$CMD_NAME --fresh' for standalone mode (no inference stack)."
echo "    Use '$CMD_NAME --help' for more info."
