# code-inference

Local inference stack for coding agents — runs opencode, Claude Code, Cursor, Codex or Grok Build
in your project against a preconfigured local `llama.cpp` stack.

## Quick install

```bash
# Latest (pre-release)
curl -sS https://raw.githubusercontent.com/jeanmachuca/code-inference/development/install.sh | sh

# Stable release (once on main):
# curl -sS https://raw.githubusercontent.com/jeanmachuca/code-inference/main/install.sh | sh
```

## Usage

From any project directory:

```bash
code-inference               # launch opencode with the inference stack
code-inference --fresh       # standalone opencode (no inference, persistent volumes)
code-inference --restart     # restart the inference stack (volumes preserved)
code-inference --full-isolation  # compose with scoped project name (inference, ephemeral)
code-inference --full-isolation --disk-name EXT1TB  # per-project volumes on an external disk
code-inference --help        # show usage
```

### Choosing an agent

`opencode` is the default. Pass `--agent` **as the first argument** to use another one:

```bash
code-inference --agent claude               # Claude Code
code-inference --agent cursor               # Cursor CLI
code-inference --agent codex                # Codex CLI
code-inference --agent grok                 # Grok Build

code-inference --agent claude --fresh       # agent alone, no inference stack
code-inference --agent codex --restart      # restart that agent's stack
```

`--agent` after a mode flag is an error, not a silent fallback:

```bash
code-inference --fresh --agent claude       # Error: --agent must be the first argument.
```

Every agent gets its own user, home and volumes, so credentials, session history and settings
never collide with opencode's or with each other's. See
[docs/agents.md](docs/agents.md) for the per-agent reference: versions, base images, volume
layout, project templates, and how to add another agent.

`--full-isolation --privileged --disk-name <disk>` additionally runs the agent with `docker.sock`
and `privileged: true`, so it can spawn nested containers — the container becomes the sandbox
boundary instead of running the agent directly on your host. See
[docs/opencode-stack.md](docs/opencode-stack.md#--privileged-running-opencode-inside-a-sandbox).

## How it works

`code-inference` is a thin wrapper around `docker compose` from this repo. It:

1. Clones the repo to `~/.code-inference/` (one-time install)
2. On each run, calls `docker compose --profile stack run --rm <agent>` from your project directory
3. Mounts your project at `/workspace` inside the agent container
4. The local inference stack (`llama.cpp` + API) runs alongside via the `stack` profile

The `--fresh` flag skips the compose stack and runs the agent standalone with persistent named
volumes. opencode pulls its published image; the other four build one locally on first run.

No Docker-in-Docker, no wrapper image, no extra daemons.

## Requirements

- Docker with Compose v2
- Git

## Install details

See [docs/installation.md](docs/installation.md) for:

- Platform-specific instructions (Linux, macOS, Windows)
- Manual install
- Uninstall
- Environment variables

## Development

See [AGENTS.md](AGENTS.md) for dev commands and repo architecture.

### Stack services

Each agent has its own compose file with the same `inference` and `api` services; only the
agent service differs.

| Service | Container | Profile | Image |
|---------|-----------|---------|-------|
| `inference` | `llama-inference` | `stack` | `ghcr.io/ggml-org/llama.cpp:server-cuda12-b9538` |
| `api` | `llama-api` | `stack` | `src/services/api/Dockerfile` |
| `opencode` | `opencode` | `tools`, `stack` | `src/opencode-stack/Dockerfile` |
| `claude` | `claude` | `tools`, `stack` | `src/claude-stack/Dockerfile` |
| `cursor` | `cursor` | `tools`, `stack` | `src/cursor-stack/Dockerfile` |
| `codex` | `codex` | `tools`, `stack` | `src/codex-stack/Dockerfile` |
| `grok` | `grok` | `tools`, `stack` | `src/grok-stack/Dockerfile` |

Agent services exist only in their own compose file — `claude` is defined in
`docker-compose-claude.yml`, not in `docker-compose.yml`. Full-isolation variants add a
`<agent>_privileged` service under the `stack_privileged` profile.

### Project templates

`code-inference` offers to create missing workspace files from `templates/<agent>-default`
when you launch an agent in a new project. Files shared by all five templates
(`docs/git-workflow.md`, `.pre-commit-config.yaml`, `dev-requirements.txt`,
`.github/workflows/`) must stay byte-identical; `scripts/check-template-sync.sh` enforces that
in pre-commit and CI.

### Quick start (development)

```bash
cp .env.example .env
# Place a GGUF in ./models/
make build && make up
```

### Tests

```bash
make test
```
