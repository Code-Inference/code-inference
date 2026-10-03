# code-inference

OpenCode AI CLI launcher — runs opencode in your project with a preconfigured local inference stack.

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
code-inference --full-isolation  # compose with scoped project name (inference, ephemeral)
code-inference --help        # show usage
```

## How it works

`code-inference` is a thin wrapper around `docker compose` from this repo. It:

1. Clones the repo to `~/.code-inference/` (one-time install)
2. On each run, calls `docker compose --profile stack run --rm opencode` from your project directory
3. Mounts your project at `/workspace` inside the opencode container
4. The local inference stack (`llama.cpp` + API) runs alongside via the `stack` profile

`--full-isolation --disk-name <disk>` scopes volumes per project and places them on an external disk. `--full-isolation --privileged --disk-name <disk>` additionally runs opencode with `docker.sock` and `privileged: true`, so it can spawn nested containers — the container becomes the sandbox boundary instead of running opencode directly on your host. See [docs/opencode-stack.md](docs/opencode-stack.md#--privileged-running-opencode-inside-a-sandbox).

The `--fresh` flag skips the compose stack and runs opencode standalone via `ghcr.io/anomalyco/opencode` with persistent named volumes.

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

| Service | Container | Profile | Image |
|---------|-----------|---------|-------|
| `inference` | `llama-inference` | `stack` | `ghcr.io/ggml-org/llama.cpp:server-cuda12-b9538` |
| `api` | `llama-api` | `stack` | `src/services/api/Dockerfile` |
| `opencode` | `opencode` | `tools` | `src/opencode-stack/Dockerfile` |

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
