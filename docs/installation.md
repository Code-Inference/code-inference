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

## Choosing an agent

The installer sets up one command that runs any of the supported agents.
`opencode` is the default; `--agent` selects another and must be the **first**
argument:

```bash
code-inference                              # opencode
code-inference --agent claude               # Claude Code
code-inference --agent cursor               # Cursor CLI
code-inference --agent codex                # Codex CLI
code-inference --agent grok                 # Grok Build
code-inference --agent hermes               # Hermes Agent
code-inference --agent pi                   # Pi coding agent
```

Each agent's image is built from this checkout on first use (opencode pulls its
published upstream image), so the first launch of an agent takes longer than
the rest.
Every agent keeps its own configuration and session history, so switching
between them — or running several at once — does not mix their state.

See [agents.md](agents.md) for versions, base images and per-agent volumes.

## Project templates

When you launch an agent in a directory that has no agent configuration yet,
`code-inference` lists the files it would create from the selected agent's
template and asks first. `--template` picks which scaffold to offer:

```bash
code-inference                               # per-agent scaffold (default)
code-inference --template workspace          # multi-repo workspace scaffold
code-inference --agent claude --template workspace
```

The workspace scaffold keeps the root as scaffolding and treats every subfolder
as its own git repository. See [agents.md](agents.md#selecting-a-scaffold---template)
for the layout.

Templates no longer carry skills. `--add-skills` installs the optional set
(`ghw` plus the five Vibe Leading skills) into the directory with
`npx skills add`, then launches the agent:

```bash
code-inference --add-skills
code-inference --agent claude --add-skills
```

It needs Node.js and network access, and runs whether or not the scaffold above
was just created. See [vibeleading.md](vibeleading.md#installing) for the paths
it writes.

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
