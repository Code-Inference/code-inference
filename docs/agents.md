# Agents

Five coding agents run on the same local inference stack. `opencode` is the
default; the other four are selected with `--agent`.

```bash
code-inference                              # opencode (default)
code-inference --agent claude               # Claude Code
code-inference --agent cursor               # Cursor CLI
code-inference --agent codex                # Codex CLI
code-inference --agent grok                 # Grok Build
```

## `--agent` must come first

`--agent` is only recognised as the **first** argument. It selects three things
at once — the compose file, the container image and the project templates — so
allowing it after a mode flag would let the agent and the mode disagree:

```bash
code-inference --agent claude --fresh    # ok
code-inference --fresh --agent claude    # Error: --agent must be the first argument.
```

It is an error rather than a silent fallback, because silently running opencode
when you asked for Claude Code is worse than refusing. `DEFAULT_AGENT` in
`start.sh` states the fallback in one place; change it there.

## Unknown flags are an error

An unrecognised flag is rejected rather than ignored:

```bash
code-inference --claude --full-isolation    # Error: unknown option '--claude'.
code-inference --agent=claude --fresh       # ok, --agent=NAME also accepted
code-inference --fresh -- --model foo       # ok, agent flags go after --
```

This matters because of what the alternative did. The parse loops stopped at the
first argument they did not recognise and handed the rest to the agent, so a
single typo swallowed every wrapper flag after it — `--privileged`,
`--full-isolation`, `--disk-name` included — and passed them to the agent
instead. The failure was silent in the worst way: the wrong agent started, at a
lower privilege level than requested, and only the agent's own `Unrecognized
flag` output hinted at the cause. `--agent=NAME` failed the same way, since
only the space form was recognised, and it defaulted to opencode.

`start.sh` validates the whole flag vocabulary up front without consuming
anything, so `--disk-name` still reaches the launcher with its value intact.

## Supported agents

| | opencode | claude | cursor | codex | grok |
|---|---|---|---|---|---|
| Product | opencode | Claude Code | Cursor CLI | Codex CLI | Grok Build |
| `--agent` value | `opencode` | `claude` | `cursor` | `codex` | `grok` |
| Binary in image | `opencode` | `claude` | `cursor-agent` | `codex` | `grok` |
| Pinned version | `2.0.22` | `2.1.289` | `2026.10.01` | `0.160.0` | `1.0.46` |
| Base image | `ghcr.io/anomalyco/opencode` | `alpine` | `debian:bookworm` | `alpine` | `alpine` |
| Runtime user | `opencode` | `claude` | `cursor` | `codex` | `grok` |
| Home | `/home/opencode` | `/home/claude` | `/home/cursor` | `/home/codex` | `/home/grok` |
| Compose service | `opencode` | `claude` | `cursor` | `codex` | `grok` |
| Compose file | `docker-compose.yml` | `docker-compose-claude.yml` | `docker-compose-cursor.yml` | `docker-compose-codex.yml` | `docker-compose-grok-build.yml` |
| Stack dir | `src/opencode-stack/` | `src/claude-stack/` | `src/cursor-stack/` | `src/codex-stack/` | `src/grok-stack/` |
| Template folder | `templates/opencode-default` | `templates/claude-default` | `templates/cursor-default` | `templates/codex-default` | `templates/grok-default` |
| Instruction file | `AGENTS.md` | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` | `AGENTS.md` |
| Published image | `ghcr.io/code-inference/code-inference` | same | same | same | same |
| Image tag suffix | *(none — owns the bare tags)* | `-claude` | `-cursor` | `-codex` | `-grok` |

Versions are pinned with `ARG` in each stack's Dockerfile. Bump the `ARG`, not
the `FROM` line, for the four agent stacks.

### Why Cursor is on Debian

Cursor's installer bundles a glibc-linked Node runtime. On Alpine (musl) it
fails at exec with `cannot execute: required file not found`. The other three
installers are self-contained and work on Alpine, so only Cursor needs glibc.

## State is per-agent

Every agent has its own user, home, container name and volumes. Nothing is
shared with opencode or with the other agents, so credentials, session history
and settings cannot collide.

| Volume | Mounted at | Holds |
|---|---|---|
| `<agent>_config` | `$HOME/.config/<agent-dir>` | settings |
| `<agent>_data` | `$HOME/.local/share/<agent-dir>` | session history |
| `<agent>_state` | `$HOME/.local/state/<agent-dir>` | runtime state |
| `<agent>_cache` | `$HOME/.cache/<agent-dir>` | caches |
| `<agent>_home` | `$HOME/.<agent-dir>` | credentials, agent-owned dotdir |

`<agent-dir>` is the agent's own directory name: `claude`, `cursor-agent`,
`codex`, `grok`. opencode uses `opencode` for all five.

`<agent>_home` exists because each CLI keeps credentials in its own dotdir
(`~/.claude`, `~/.codex`, ...), which the four XDG mounts above do not cover.
It must be a named volume: a bind mount here would be read as a *host* path by
Docker, which does not exist.

`model_data`, `model_hf_data` and `training_data` are **not** per-agent — they
belong to the inference stack, which every agent shares.

Because opencode keeps `/home/opencode` and its existing volume names, adding
these agents needs no migration and does not touch current opencode state.

## Modes

All four modes work with every agent:

```bash
code-inference --agent claude                    # agent + inference stack
code-inference --agent claude --fresh            # agent alone, persistent volumes
code-inference --agent claude --full-isolation   # per-project volumes
code-inference --agent claude --restart          # restart that agent's stack
code-inference --agent claude --full-isolation --privileged --disk-name EXT1TB
```

`--restart` takes the agent's compose file, so `--restart --agent cursor`
restarts the Cursor stack, not the opencode one. `start.sh` passes the compose
basename to `restart.sh` via an internal `--compose` flag, which keeps the
agent mapping in one place.

`--privileged` has the same constraints as for opencode: it requires
`--full-isolation` and `--disk-name`, and grants `docker.sock` + `privileged: true`
+ root. See [opencode-stack.md](opencode-stack.md#--privileged-running-opencode-inside-a-sandbox).

## `--fresh` builds from the Dockerfile

`launch-fresh-<agent>.sh` builds `code-inference-<agent>-fresh` from
`src/<agent>-stack/Dockerfile` on first use and reuses it afterwards.

```bash
docker images | grep fresh
# code-inference-claude-fresh   latest
```

The build is layer-cached, so it is fast when nothing has changed. To force a
rebuild after editing the stack Dockerfile:

```bash
docker rmi code-inference-claude-fresh
```

**It builds rather than pulls, deliberately.** Images for all five stacks are
published to `ghcr.io/code-inference/code-inference`, and `--fresh` does not use
them. Building from this checkout means `--fresh` always matches the Dockerfile
and toolchain in the repository you are running from — edit
`src/<agent>-stack/Dockerfile` and the change takes effect, instead of a registry
tag quietly deciding which toolchain you get.

opencode is the exception: `launch-fresh-opencode.sh` runs the published
`ghcr.io/anomalyco/opencode` image, because opencode ships and versions that
image upstream rather than building it here.

## Project templates

`code-inference` bootstraps a new workspace from `templates/<agent>-default`,
offering to create any file the folder ships that is missing. The list is read
from the folder, so adding a file to a template is enough to have it offered.

Each agent needs its own template because the instruction file and its path
differ, and because agents only auto-load the paths they recognise:

| Agent | Auto-loads | Git workflow shipped at |
|---|---|---|
| opencode | `AGENTS.md`, `.opencode/instructions/*.md`, `opencode.json` | `.opencode/instructions/git-workflow.md` |
| claude | `CLAUDE.md`, `.claude/rules/*.md` | `.claude/rules/git-workflow.md` |
| cursor | `AGENTS.md`, `.cursor/rules/*.mdc` | `.cursor/rules/git-workflow.mdc` |
| codex | `AGENTS.md` only | `docs/git-workflow.md` (referenced, not auto-loaded) |
| grok | `AGENTS.md` only | `docs/git-workflow.md` (referenced, not auto-loaded) |

Two details worth knowing:

- A plain `.md` file in `.cursor/rules` is **ignored** by Cursor — it must be
  `.mdc` with frontmatter. The cursor template ships `.mdc` with
  `alwaysApply: true`.
- Codex and Grok have no rules directory, so their templates ship the workflow at
  `docs/git-workflow.md` and say in `AGENTS.md` that it must be read before
  committing. It is not auto-loaded; claiming otherwise would be misleading.

The files every template shares — `docs/git-workflow.md`,
`.pre-commit-config.yaml`, `dev-requirements.txt` and `.github/workflows/` —
must stay byte-identical across all five, or two agents would follow different
rules in the same repository. `scripts/check-template-sync.sh` enforces this in
pre-commit and CI.

## Adding an agent

1. `src/<agent>-stack/Dockerfile` — copy `src/claude-stack/Dockerfile` as the
   Alpine starting point. Set `ENV AGENT_BIN=<binary>`. Create a user named for
   the agent with home `/home/<agent>`, and create the XDG directories so
   volumes mount when empty. Version-pin with an `ARG`.
2. `Dockerfile_privileged` in the same dir — identical except `USER root`.
3. `src/common/entrypoint.sh` needs no change; it execs `$AGENT_BIN`.
4. `docker-compose-<agent>.yml` and `docker-compose-<agent>-full-isolation.yml` —
   copy an existing pair. The service, container and volumes must all carry the
   agent name. Validate with `docker compose -f <file> config -q`.
5. `launch-<agent>.sh` and `launch-fresh-<agent>.sh` — copy
   `launch-claude-code.sh`. The fresh launcher builds
   `src/<agent>-stack/Dockerfile` to `code-inference-<agent>-fresh`.
6. `templates/<agent>-default/` — copy `templates/claude-default/`, then replace
   the instruction file with the one the agent actually reads.
7. `start.sh` — add the agent to `AGENT_NAMES` and to `agent_template_dir`,
   `agent_compose`, `agent_launcher` and `agent_fresh_launcher`. Keep those five
   in sync; they are the only places an agent name is spelled out.
8. Verify: `shellcheck -s sh start.sh launch-<agent>*.sh`,
   `docker compose -f docker-compose-<agent>.yml config -q`, then build and run
   the service and confirm the agent reports its version.

## Entrypoint

`src/common/entrypoint.sh` is the single entrypoint for **all five** stacks,
and ends in:

```sh
exec "${AGENT_BIN:-opencode}" "$@"
```

Each stack's Dockerfile sets `ENV AGENT_BIN=<binary>`. opencode sets nothing,
so `${AGENT_BIN:-opencode}` resolves to `opencode` — one file, no per-agent
variants, and a bootstrap fix lands once instead of five times.

The opencode stack kept a duplicate of this file while the stacks were being
split out, so its image would be untouched. It was verified byte-identical in
the built image and then removed, along with `scripts/check-entrypoint-sync.sh`,
which existed only to catch one-sided edits between the two copies.