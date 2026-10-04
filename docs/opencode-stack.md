# OpenCode stack

OpenCode AI CLI as a Docker Compose service (`tools` profile). Runs from any directory by mounting the host's current directory as `/workspace`.

## Quick start

```bash
# From this repo:
./launch-opencode.sh

# Scoped to this project, state on an external disk:
./launch-opencode.sh --full-isolation --disk-name EXT1TB

# Sandboxed with nested-Docker capability (requires both flags above):
./launch-opencode.sh --full-isolation --privileged --disk-name EXT1TB

# From any directory with this compose file available:
docker compose --profile stack run --rm opencode

# Without the compose file (no persistent volumes):
docker run -it --rm -v "$(pwd)":/workspace ghcr.io/anomalyco/opencode:2.0.22
```

## Dockerfile (`src/opencode-stack/Dockerfile`)

| Step | Detail |
|------|--------|
| **Base** | `ghcr.io/anomalyco/opencode:2.0.22` — the published OpenCode CLI image, pinned via `ARG OPENCODE_VERSION`. (Project moved from archived `opencode-ai/opencode` to `anomalyco/opencode`.) |
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

**v2 footguns, both silent (no error, no warning):**

1. **`capabilities` is only honored inside a top-level `providers` map.** Under a v1 `provider` map it is parsed and discarded, so the model loses its tool support. This still applies on 2.0.22.
2. **`input`/`output` alongside `tools` are belt-and-braces.** On 2.0.6 a model declaring only `{"tools": true}` dropped the *entire provider* (`providers` resolved to `{}`). Fixed upstream by 2.0.22, but the template keeps all three so it is safe on either version.

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
| `launch-opencode.sh` | `docker compose --profile stack run --rm` | `workspace` bind | ✅ Config, auth, cache persist |
| `launch-opencode.sh --full-isolation` | `docker compose -p <dirname> -f docker-compose-full-isolation.yml` | Per-project bind mounts | ✅ Scoped per project |
| `launch-opencode.sh --full-isolation --disk-name <disk>` | Same, volumes rooted on an external disk | Per-project, on `<disk>` | ✅ Scoped per project and per disk |
| `launch-opencode.sh --full-isolation --privileged --disk-name <disk>` | Same, `opencode_privileged` service | Same | ✅ Plus nested Docker (see below) |
| `launch-fresh-opencode.sh` | `docker run -it --rm -v $(pwd):/workspace` | Named volumes | ✅ Config, auth, cache persist |

### launch-opencode.sh

```sh
docker compose -f "$COMPOSE_FILE" -p "$NAME_SUFFIX" --profile "$PROFILE_NAME" \
  run --rm --name "opencode-$NAME_SUFFIX" --build --remove-orphans "$SERVICE_NAME"
```

- `--name "opencode-<dirname>"` avoids container name collision across directories.
- Launcher flags may be given in **any order** and combine freely. Parsing stops at the first
  unrecognized argument, so `--` passes everything after it straight to opencode:
  `code-inference -- --continue`.
- `--disk-name` without a value is an error rather than a silent fallback.

`--full-isolation` selects `docker-compose-full-isolation.yml`, where every volume is a bind
mount scoped by `NAME_SUFFIX` (`<project>_opencode_config`, and so on). `NAME_SUFFIX` comes from
`basename "$PWD"`, so each project gets its own set.

`--disk-name NAME` moves those bind mounts onto an external disk at
`/Volumes/<NAME>/docker_data/`. This is the point of the flag: the disk may be empty, may hold
unrelated data, and keeps project state off the boot volume.

#### External-disk volumes are created before launch

Because these are bind mounts (`type: none`, `o: bind`), Docker cannot create a missing host path
itself — the mount fails before the container starts:

```
failed to mount local volume: mount /Volumes/EXT1TB/docker_data/myproj_opencode_config:
no such file or directory
```

`launch-opencode.sh` therefore runs `mkdir -p` on those paths before invoking compose. This is
host-side, so it cannot live in the image; the Dockerfile's `mkdir` only covers in-container XDG
directories.

- Paths are **parsed from the compose file's `device:` lines**, not hardcoded, so a newly added
  volume cannot silently fail to mount.
- Only external-disk paths are created. `${PWD}` and `${PWD}/models` belong to your workspace and
  are left alone.
- An **unmounted `--disk-name` is rejected** with a clear error. Without that check a typo would
  `mkdir -p` a fresh `/Volumes/<typo>` on the root disk and quietly write state there.

Converting these to named volumes would also dodge the problem, but it would defeat the purpose of
`--disk-name`, so `mkdir -p` is the intended mechanism.

### `--privileged`: running opencode inside a sandbox

```sh
code-inference --full-isolation --privileged --disk-name EXT1TB
```

Runs the `opencode_privileged` service with `docker.sock`, `privileged: true`, and `user: root`, so
the agent can spawn nested containers and write root-owned files **inside the container**.

**The container is the sandbox boundary.** The host is what this protects. The alternative is
running opencode directly on the host, where a bad command or a hallucinated path can touch
anything on the filesystem; here the damage is bounded by the container and the bind mounts.

It grants host-equivalent access, so it is **opt-in and constrained**:

- `--privileged` **requires** `--full-isolation`. Without it the stack shares `${PWD}` and the
  default volume root with every other project, which is the opposite of the isolation this mode
  depends on.
- `--privileged` **requires** `--disk-name`. Without it the launcher silently falls back to the
  local compose file and the shared volume root.
- `opencode_privileged` and the `stack_privileged` profile exist **only** in
  `docker-compose-full-isolation.yml`. A direct
  `docker compose -f docker-compose.yml --profile stack_privileged run` finds nothing, so the
  constraint survives even if the launcher is bypassed.

Treat it as trusted-workspace-only. It also mounts `~/.ssh` read-only, so SSH keys are readable by
the agent.

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
- **`invalid project name "<dir>"`** — `NAME_SUFFIX` is `basename "$PWD"` verbatim, and compose requires `[a-z0-9][a-z0-9_-]*`. A leading dot fails, so running from `~/.code-inference` (project name `.code-inference`) is rejected. Run from a normally-named directory, or pass a sanitized name.
- **`failed to mount local volume: ... no such file or directory`** — The external-disk path doesn't exist. With `--disk-name` the launcher creates these itself; check the disk is actually mounted, since a typo is now rejected outright.
- **`--privileged requires --full-isolation`** — By design. `--privileged` runs a host-equivalent container, so it is only offered alongside an isolated stack. See [`--privileged`](#--privileged-running-opencode-inside-a-sandbox).
