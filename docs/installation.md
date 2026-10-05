# Installation

## Prerequisites

- **Docker** with Compose v2 (included with Docker Desktop, or `docker compose` plugin)
- **Git** (for `install.sh` or manual clone)

Verify:

```bash
docker info >/dev/null && docker compose version
```

## Choose your branch

| Branch | Use case | Command |
|--------|----------|---------|
| `main` | Stable release | `main` in URL |
| `development` | Latest (pre-release) | `development` in URL |

The examples below use `development`. Replace with `main` for the stable release.

## Quick install (Linux / macOS)

```bash
curl -sS https://raw.githubusercontent.com/Code-Inference/code-inference/development/install.sh | sh
```

This clones the repo to `~/.code-inference/` and places a `code-inference` wrapper in `/usr/local/bin/`.

You may be prompted for `sudo` if `/usr/local/bin/` is not writable by your user.

### Verify

```bash
code-inference --help
```

## Platform details

### macOS

| Detail | Value |
|--------|-------|
| Bin dir | `/usr/local/bin` (default, may need sudo) |
| Alt bin dir | `~/bin` — set `BIN_DIR=$HOME/bin` |
| Docker | Docker Desktop required |
| Socket | `docker compose` handles socket automatically |

Install to `~/bin` (no sudo):

```bash
BIN_DIR="$HOME/bin" curl -sS https://raw.githubusercontent.com/Code-Inference/code-inference/development/install.sh | sh
```

Make sure `~/bin` is on your `PATH` (add to `~/.zshrc`):

```bash
export PATH="$HOME/bin:$PATH"
```

### Linux

| Detail | Value |
|--------|-------|
| Bin dir | `/usr/local/bin` (default, may need sudo) |
| Docker | `docker` + `docker compose` plugin required |
| Socket | `/var/run/docker.sock` — accessible by default |

Install without sudo to `~/.local/bin`:

```bash
BIN_DIR="$HOME/.local/bin" curl -sS https://raw.githubusercontent.com/Code-Inference/code-inference/development/install.sh | sh
```

### Windows

Use **Git Bash** or **WSL2**.

#### Git Bash

```bash
BIN_DIR="$HOME/bin" curl -sS https://raw.githubusercontent.com/Code-Inference/code-inference/development/install.sh | sh
```

Add `~/bin` to your `PATH` in `~/.bashrc`:

```bash
export PATH="$HOME/bin:$PATH"
```

#### WSL2 (Ubuntu)

Same as Linux install. Ensure Docker Desktop for Windows has WSL2 integration enabled.

## Manual install

If you prefer not to pipe through `curl`:

```bash
git clone https://github.com/Code-Inference/code-inference.git ~/.code-inference
sudo ln -s ~/.code-inference/start.sh /usr/local/bin/code-inference
```

Or create a wrapper manually:

```bash
cat > /usr/local/bin/code-inference <<'EOF'
#!/bin/sh
exec "$HOME/.code-inference/start.sh" "$@"
EOF
chmod +x /usr/local/bin/code-inference
```

## Uninstall

```bash
rm -rf ~/.code-inference
rm /usr/local/bin/code-inference
```

If you used a custom `INSTALL_DIR` or `BIN_DIR`, adjust accordingly.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTALL_DIR` | `$HOME/.code-inference` | Where the repo is cloned |
| `BIN_DIR` | `/usr/local/bin` | Where the wrapper is placed |
| `CMD_NAME` | `code-inference` | Name of the command |
