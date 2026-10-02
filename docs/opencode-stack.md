# OpenCode stack

OpenCode AI CLI as a Docker Compose service (`tools` profile). Runs from any directory by mounting the host's current directory as `/workspace`.

## Quick start

```bash
# From this repo:
./launch-opencode.sh

# From any directory with this compose file available:
docker compose --profile tools run --rm opencode

# Without the compose file (no persistent volumes):
docker run -it --rm -v "$(pwd)":/workspace ghcr.io/anomalyco/opencode:2.0.6
```

## Dockerfile (`src/opencode-stack/Dockerfile`)

| Step | Detail |
|------|--------|
| **Base** | `ghcr.io/anomalyco/opencode:2.0.6` — the published OpenCode CLI image, pinned via `ARG OPENCODE_VERSION`. (Project moved from archived `opencode-ai/opencode` to `anomalyco/opencode`.) |
| **Git** | `apk add --no-cache git` — needed for opencode's git-aware features |
| **User** | Non-root `opencode` user (fixed uid/gid, no host mapping) |
| **XDG dirs** | `~/.config/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`, `~/.cache/opencode` — created with `opencode` ownership so volumes mount correctly even when empty |
| **Workdir** | `/workspace` — matches the compose mount target |

**Note on uid/gid:** The `opencode` user has a fixed uid inside the image. If your host files are owned by a different uid, the container can still read/write them on most Linux setups (bind mount shares the host uid), but files created by opencode inside the container will be owned by the container's `opencode` uid. For strict host uid alignment, some community setups map uid/gid via `--build-arg UID=$(id -u) --build-arg GID=$(id -g)`.

## Config format (`templates/default/opencode.json`)

The template uses the **native v2** config shape. OpenCode 2 still reads v1 syntax and normalizes it in memory, but that fallback silently drops some fields — do not mix the two formats.

| v1 | v2 |
|----|----|
| `provider` | `providers` |
| `npm: "@ai-sdk/openai-compatible"` | `package: "aisdk:@ai-sdk/openai-compatible"` |
| `options: { baseURL }` | `settings: { baseURL }` |
| `supportsToolCalls` / `tool_call` | `capabilities.tools` |

**Two v2 footguns, both silent (no error, no warning):**

1. **`capabilities` is only honored inside a top-level `providers` map.** Under a v1 `provider` map it is parsed and discarded, so the model loses its tool support.
2. **`capabilities` requires `input` and `output` alongside `tools`.** Supplying `{"tools": true}` on its own drops the *entire provider* (`providers` resolves to `{}`).

Verify a config change against the real image rather than by inspection. Mount the file read-only — OpenCode writes a `service.json` credential into its config dir on first run, so mounting the directory would drop a secret into your repo:

```bash
docker run --rm --entrypoint opencode --user opencode \
  -e XDG_CONFIG_HOME=/home/opencode/.config \
  -v "$PWD/templates/default/opencode.json":/home/opencode/.config/opencode/opencode.json:ro \
  code-inference-opencode:latest debug config
```

Expect all three providers (`opencode`, `code-inference`, `code-inference-hf`) and a `capabilities` block on `model.gguf`.

## Compose service (`docker-compose.yml` opencode service)

```yaml
opencode:
    container_name: opencode
    profiles:
      - tools
    build:
      context: .
      dockerfile: src/opencode-stack/Dockerfile
    stdin_open: true   # -i (interactive)
    tty: true           # -t (pseudo-TTY)
    user: opencode
    environment:
      - XDG_CONFIG_HOME=/home/opencode/.config
      - XDG_DATA_HOME=/home/opencode/.local/share
      - XDG_STATE_HOME=/home/opencode/.local/state
      - XDG_CACHE_HOME=/home/opencode/.cache
    networks:
      - internal
    volumes:
      - ${PWD}:/workspace
```

| Setting | Purpose |
|---------|---------|
| `stdin_open: true` + `tty: true` | Interactive TTY — required for the CLI to receive input |
| `user: opencode` | Matches the Dockerfile's non-root user |
| `XDG_*_HOME` | Points opencode to the directories the Dockerfile created |
| `network: internal` | Shares the bridge network with `inference` and `api` — opencode can reach `http://api:8000` |
| `${PWD}:/workspace` | Mounts whatever directory you run `docker compose` from |

**No persistent volumes are mounted by this service.** Each `run --rm` starts with fresh XDG directories (empty, correct ownership). Config, auth tokens, and cache are ephemeral.

> For persistent volumes across sessions, use `launch-fresh-opencode.sh` (standalone `docker run` with named volumes).

## Volumes

Four named volumes are declared in `docker-compose.yml` but **not attached to any service**:

| Volume | Container path | Stores |
|--------|---------------|--------|
| `opencode_config` | `/home/opencode/.config/opencode` | `opencode.json`, agents, plugins |
| `opencode_data` | `/home/opencode/.local/share/opencode` | `auth.json` (provider tokens) |
| `opencode_state` | `/home/opencode/.local/state/opencode` | Session state |
| `opencode_cache` | `/home/opencode/.cache/opencode` | Temporary caches |

These exist as a convenience for the standalone `launch-fresh-opencode.sh` script but are dead declarations in the compose context — no compose service references them. To attach them, add `volumes:` entries to the opencode service.

## Launcher scripts

| Script | Mechanism | Volumes | Persistence |
|--------|-----------|---------|-------------|
| `launch-opencode.sh` | `docker compose --profile tools run --rm` | None (ephemeral) | ❌ Nothing saved |
| `launch-opencode.sh --full-isolation` | `docker compose -p <dirname> --profile tools run --rm` | Scoped per-project volumes | ❌ Still none mounted |
| `launch-fresh-opencode.sh` | `docker run -it --rm -v $(pwd):/workspace` | Named volumes | ✅ Config, auth, cache persist |

### launch-opencode.sh

```sh
docker compose $PROJECT_FLAG --profile tools run --rm --name "opencode-$NAME_SUFFIX" opencode
```

- No persistent volumes — each run is fresh.
- `--name "opencode-<dirname>"` avoids container name collision across directories.
- `--full-isolation` adds `-p <dirname>` scoping, which affects compose project name for volume/label scoping but has no practical effect since no volumes are mounted.

### launch-fresh-opencode.sh

```sh
docker run -it --rm -v $(pwd):/workspace \
  -v opencode_config:/home/opencode/.config/opencode \
  -v opencode_data:/home/opencode/.local/share/opencode \
  -v opencode_state:/home/opencode/.local/state/opencode \
  -v opencode_cache:/home/opencode/.cache/opencode \
  ghcr.io/anomalyco/opencode
```

- Uses `docker run` directly (not compose). Works from any directory without the compose file.
- Mounts the four named volumes for persistent config, auth, cache, and state.
- **Name "fresh" is misleading** — with volumes, state persists across runs.

## Permission hardening

OpenCode's default permission model **allows all operations** without approval. Community and official guidance recommends restricting this:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": "ask",
    "bash": "ask"
  }
}
```

Add these to `opencode.json` (global at `~/.config/opencode/opencode.json` or per-project `opencode.json`) to require confirmation before file edits and shell commands. See [official permissions docs](https://opencode.ai/docs/permissions).

## Config precedence

OpenCode loads config in this order (later overrides earlier):

1. **Remote** (`.well-known/opencode` — organizational defaults)
2. **Global** (`~/.config/opencode/opencode.json`)
3. **Custom** (`OPENCODE_CONFIG` env var)
4. **Project** (`opencode.json` in workspace root)
5. **`.opencode` directories** — agents, commands, plugins
6. **Inline** (`OPENCODE_CONFIG_CONTENT` env var)
7. **Managed** (system path, MDM — highest priority, not user-overridable)

When running from this repo, opencode picks up `/workspace/opencode.json` (project config), which overrides global defaults. If you need shared auth tokens and custom agents across projects, place them in `~/.config/opencode/opencode.json` or use the compose volume mounts.

See the [official config docs](https://opencode.ai/docs/config) for the full schema.

## Git operations

Git is installed intentionally so opencode can autonomously commit, push, branch, and perform other git operations during a session. The bind mount `${PWD}:/workspace` shares the host's `.git` directory with the container.

**Authentication depends on the remote protocol:**
- **HTTPS remotes** — usually work out of the box (git uses `credential.helper` or prompts interactively).
- **SSH remotes** — require the host SSH agent to be forwarded into the container.
- **GitHub Copilot / OpenCode auth** — opencode can authenticate via its own provider tokens (`opencode auth login`), independent of git credentials.

If you use SSH-based git remotes, add to the compose service:
```yaml
volumes:
  - $SSH_AUTH_SOCK:/ssh-agent
environment:
  - SSH_AUTH_SOCK=/ssh-agent
```

> **macOS → Linux SSH config caveat:** macOS `~/.ssh/config` often contains `UseKeychain yes` (macOS-only). On Linux, this is an invalid option and causes SSH to abort. If git operations fail in the container with `Bad configuration option: usekeychain`, either remove those lines from your SSH config (they're macOS-only) or copy a filtered config before pushing, e.g. `cp ~/.ssh/config /tmp/ssh_config && sed -i '/UseKeychain/d' /tmp/ssh_config && GIT_SSH_COMMAND="ssh -F /tmp/ssh_config" git push`. The fix is local to the container; your host config is unaffected.

## Network

The `internal` bridge network gives the opencode container access to `http://api:8000` and `http://inference:8080`. This is how opencode reaches the local inference stack when configured with `baseURL: http://api:8000/v1` in `opencode.json`.

## `opencode.json`

This repo's `opencode.json` (gitignored; see `opencode.json.example` for the template) configures:
- **Provider:** `code-inference` via `@ai-sdk/openai-compatible`, pointing to `http://api:8000/v1`
- **Model:** `qwen2.5-coder-3b-instruct-q4_k_m.gguf` with tool call support, 64K context, 32K output
- **Instructions:** `AGENTS.md` + `.opencode/instructions/git-workflow.md`

When running opencode from this repo, these settings are auto-loaded. From another directory, create your own `opencode.json`.

## Troubleshooting

- **"container name already exists"** — Another opencode instance is still running. Exit it or remove with `docker rm opencode-<name>`. With `--full-isolation`, container names are unique per directory.
- **Permission denied writing to workspace** — The bind-mounted `${PWD}` may be owned by a different host user. The container runs as `opencode` (uid 1000 typically). If your host files are owned by another user, opencode can still read/write them on most setups, but restrictive permissions may require `chmod` on the host directory.
- **No auth provider configured** — First-time run needs `opencode auth login` unless the stack is already running and `opencode.json` is present.
