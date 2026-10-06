#!/usr/bin/env sh
# Shared bootstrap script for every agent stack (opencode, claude, codex,
# cursor, grok).
# Run after container rebuild to restore tooling config.
#
# The agent binary to exec is taken from AGENT_BIN, defaulting to opencode,
# so each stack's Dockerfile only has to set that variable.
#
# Credential handling:
#   - GH_TOKEN is exported so tools like gh and git can use it,
#     but only sourced from gh's own config file (not stored here).
#   - SSH config is copied to a restricted-permission temp file
#     to strip macOS-only directives; cleaned up on exit.
#   - The profile block uses a unique marker for idempotency
#     so it is only appended once.

set -eu

MARKER='# --- code-inference bootstrap ---'

ssh_cleanup() {
  if [ -n "${SSH_TMP:-}" ] && [ -f "$SSH_TMP" ]; then
    rm -f "$SSH_TMP"
  fi
  if [ -n "${GH_SSH_HOME:-}" ] && [ -d "$GH_SSH_HOME" ]; then
    rm -rf "$GH_SSH_HOME"
  fi
  if [ -n "${KNOWN_HOSTS_DIR:-}" ] && [ -d "$KNOWN_HOSTS_DIR" ]; then
    rm -rf "$KNOWN_HOSTS_DIR"
  fi
}
trap ssh_cleanup EXIT

# ── 1. ~/.profile ──────────────────────────────────────────────────────────────

if [ ! -f "$HOME/.profile" ] || ! grep -qF "$MARKER" "$HOME/.profile" 2>/dev/null; then
  echo ">>> Creating ~/.profile with GH_TOKEN and SSH workaround..."
  cat << EOF >> "$HOME/.profile"

$MARKER
# Export GH_TOKEN from gh hosts.yml for API auth
if [ -f "\$HOME/.config/gh/hosts.yml" ]; then
  export GH_TOKEN=\$(grep oauth_token "\$HOME/.config/gh/hosts.yml" | head -1 | awk '{print \$2}')
fi

# SSH config workaround (Linux container, macOS host with UseKeychain)
if [ -f "\$HOME/.ssh/config" ] && grep -q UseKeychain "\$HOME/.ssh/config" 2>/dev/null; then
  SSH_TMP=\$(mktemp /tmp/ssh_config.XXXXXX)
  chmod 600 "\$SSH_TMP"
  cp "\$HOME/.ssh/config" "\$SSH_TMP" && sed -i '/UseKeychain/d' "\$SSH_TMP"
  export GIT_SSH_COMMAND="ssh -F \$SSH_TMP"
fi
$MARKER
EOF
fi

# Source so it takes effect immediately
# shellcheck source=/dev/null
. "$HOME/.profile"

# ── 2. SSH known_hosts ───────────────────────────────────────────────────────────

echo ">>> ~/.ssh is a Docker ro mount; using temp SSH dir for known_hosts..."
KNOWN_HOSTS_DIR=$(mktemp -d /tmp/ssh-keyscan-XXXXXX)
cp -r "$HOME/.ssh/." "$KNOWN_HOSTS_DIR/" 2>/dev/null || true
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=$KNOWN_HOSTS_DIR/known_hosts -o StrictHostKeyChecking=accept-new"

if ! grep -q '^github.com ' "$KNOWN_HOSTS_DIR/known_hosts" 2>/dev/null; then
  echo ">>> Adding github.com to SSH known_hosts..."
  ssh-keyscan github.com >> "$KNOWN_HOSTS_DIR/known_hosts" 2>/dev/null || echo ">>> Warn: could not fetch github.com SSH key (network unavailable?)"
fi

# ── 3. gh auth (interactive only) ──────────────────────────────────────────────

if [ -t 0 ] && ! gh auth status >/dev/null 2>&1; then
  echo ""
  echo ">>> gh is not authenticated."
  echo ">>> Starting device-code login flow..."
  echo ""

  if [ ! -w "$HOME/.ssh" ] 2>/dev/null; then
    echo ">>> ~/.ssh is not writable (Docker ro mount); using temp SSH dir..."
    GH_SSH_HOME=$(mktemp -d /tmp/gh-home-XXXXXX)
    mkdir -p "$GH_SSH_HOME/.ssh"
    cp -r "$HOME/.ssh/." "$GH_SSH_HOME/.ssh/" 2>/dev/null || true
    chmod 700 "$GH_SSH_HOME/.ssh"
    ORIG_HOME="$HOME"
    HOME="$GH_SSH_HOME"
  fi

  gh auth login --git-protocol ssh --web

  if [ -n "${ORIG_HOME:-}" ]; then
    KEY_FILE=$(ls "$HOME/.ssh/id_ed25519" 2>/dev/null || ls "$HOME/.ssh/id_rsa" 2>/dev/null || true)
    if [ -n "$KEY_FILE" ]; then
      echo ">>> Configuring GIT_SSH_COMMAND to use generated key..."
      export GIT_SSH_COMMAND="ssh -i $KEY_FILE -o StrictHostKeyChecking=accept-new"
    fi
    HOME="$ORIG_HOME"
    unset ORIG_HOME
  fi

  echo ""
  echo ">>> Re-sourcing profile to pick up GH_TOKEN..."
  . "$HOME/.profile"
  echo ">>> GH_TOKEN: ${GH_TOKEN:+set}"
fi

# ── 4. Git committer identity ───────────────────────────────────────────────────

CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$CURRENT_NAME" ] || [ -z "$CURRENT_EMAIL" ]; then
  echo ""
  echo ">>> Git committer identity is not fully configured."
  echo "    (name: ${CURRENT_NAME:-<unset>}, email: ${CURRENT_EMAIL:-<unset>})"
fi

if [ -t 0 ]; then
  if [ -z "$CURRENT_NAME" ]; then
    printf "Enter your full name for git commits: "
    read -r INPUT_NAME
    if [ -n "$INPUT_NAME" ]; then
      git config --global user.name "$INPUT_NAME"
    fi
  fi

  if [ -z "$CURRENT_EMAIL" ]; then
    printf "Enter your email for git commits: "
    read -r INPUT_EMAIL
    if [ -n "$INPUT_EMAIL" ]; then
      git config --global user.email "$INPUT_EMAIL"
    fi
  fi

  echo ""
  echo "=== Setup complete ==="
  echo "GH_TOKEN: ${GH_TOKEN:+set}"
  echo "GIT_SSH_COMMAND: ${GIT_SSH_COMMAND:+set}"
  echo "Git user: $(git config --global user.name 2>/dev/null || echo '<unset>') <$(git config --global user.email 2>/dev/null || echo '<unset>')>"
fi

exec "${AGENT_BIN:-opencode}" "$@"
