# SDLC: code-inference-ai

## Overview

Local/on-premise code inference stack. Development is Docker-native — the only runtime dependency is Docker with Compose v2. All artifacts are container images; host installs are limited to dev tooling.

## Git workflow

- **Default branch:** `development`. Integration branch for all feature work.
- **`main`:** Release-only. Receives `development` via release PR.
- **Topic branches:** Branch from `development`: `feature/<topic>`, `fix/<topic>`, `bugfix/<topic>`.
- **No rebase.** Use `git pull` (merge) to sync.
- **Keep merged branches.** Do not delete topic branches after merge.
- **Versioning:** [Semantic Versioning 2.0.0](https://semver.org).
  - **PATCH** (`v1.0.0` → `v1.0.1`): Bug fixes, refactors, docs, CI, non-functional changes.
  - **MINOR** (`v1.0.0` → `v1.1.0`): New features, additions, backwards-compatible enhancements.
  - **MAJOR** (`v1.0.0` → `v2.0.0`): Breaking changes — API, config format, interface, behaviour.
- **Tags:** Annotated SemVer.
  - Release: `vMAJOR.MINOR.PATCH` on `main`.
  - Integration: `vMAJOR.MINOR.PATCH-dev.N` on `development` after feature merge.
- **Normative reference:** `docs/git-workflow.md` (when written). Local agent instructions in `.opencode/instructions/git-workflow.md`.

## Local development

### Prerequisites

- Docker with Compose v2
- Python 3.12 (for pre-commit / lint / typecheck outside Docker)

### Setup

```
cp .env.example .env
# Place a GGUF model in ./models/ (see docs/models/README.md)
make build && make up
```

### Environment variables (`.env`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `MODEL_FILENAME` | `model.gguf` | GGUF file loaded by llama-server |
| `CONTEXT_SIZE` | `1024` | llama-server context window |
| `MAX_TOKENS` | `256` | Max tokens for inference |
| `THREADS` | `2` | CPU threads for llama-server |
| `INFERENCE_URL` | `http://inference:8080` | API → inference backend URL |
| `RATE_LIMIT_PER_MINUTE` | `30` | Rate limit on POST /v1/chat/completions |
| `MAX_PROMPT_CHARS` | `8000` | Char-level truncation threshold |
| `API_PORT` | `8000` | Host port for the API service |

## Code quality gates

Runs in order: `shellcheck` → `sync checks` → `lint` → `typecheck` → `test`. All enforced in CI
and available locally.

### 1. Pre-commit hooks (local only)

```
pip install -r dev-requirements.txt && pre-commit install
pre-commit run --all-files
```

Hooks: template-sync, entrypoint-sync (local), trailing-whitespace, end-of-file-fixer,
check-yaml, check-added-large-files (500 KB max), ruff (with `--fix`), ruff-format, mypy.

### 2. Shellcheck (all shell scripts)

```
shellcheck -s sh start.sh restart.sh install.sh launch-*.sh scripts/*.sh
```

The launcher scripts are the user-facing entry points and are pure shell, so this is the only
thing that checks them. `install.sh` originally had a `for cmd in docker` single-item loop,
which this caught.

### 3. Duplication guards

```
./scripts/check-template-sync.sh    # shared template files identical across all 5 agents
./scripts/check-entrypoint-sync.sh  # the two entrypoint copies agree
```

Both are pre-commit hooks and CI lint steps. They exist because the repository intentionally
carries duplicated files — five per-agent templates sharing seven files, and two copies of the
container entrypoint — and duplication without a check drifts silently. If one reports drift,
copy the correct version to the others rather than editing the script.

### 4. Lint (ruff)

```
ruff check .           # lint
ruff format --check .  # formatting
```

Config in `pyproject.toml`: line-length 100, target py312, single quotes, select `E,F,I,N,W,UP,SIM`.

### 5. Typecheck (mypy)

```
mypy src/
```

Runs with `--no-strict-optional --ignore-missing-imports`. Additional deps (pydantic, httpx, fastapi, slowapi, pydantic-settings) declared in `.pre-commit-config.yaml` for the pre-commit mypy hook.

### 6. Test

```
make test
# or directly:
docker compose --profile stack run --rm --no-deps api pytest -v
```

- Unit tests only — no inference service required (`--no-deps`).
- Single test file: `tests/api/test_prompt.py` (3 tests: PII masking, intent tagging, truncation).
- Pytest config lives in two places:
  - Root `pytest.ini` / `pyproject.toml`: `pythonpath = src/services/api` — for CI and host-local runs.
  - `src/services/api/pytest.ini`: `pythonpath = .` — for in-container runs.
- Runtime dependencies (including pytest) in `src/services/api/requirements.txt`.
- Dev-only tools in `dev-requirements.txt` (pre-commit, ruff, mypy).

### Adding new tests

- Place files in `tests/api/test_*.py`.
- Import from `app.<module>` (the `pythonpath` setting resolves `src/services/api`).
- Add new runtime deps to `src/services/api/requirements.txt`.

## CI pipeline

### Trigger summary

| Trigger | Workflow | What it does |
|---------|----------|-------------|
| Push to `feature/**`, `fix/**`, `bugfix/**` | `open-pr-to-development.yml` | Auto-opens a PR into `development` if none exists |
| Push/PR to `development` or `main` | `ci.yml` | Runs lint + test checks |
| PR targeting `main` | `main-pr-source.yml` | Rejects PRs whose head branch is not `development` |

### `ci.yml`

Triggers: push or PR to `main` or `development`.

#### Jobs

1. **lint** — shellcheck, then both sync guards, then installs `src/services/api/requirements.txt` + `dev-requirements.txt` and runs ruff check, ruff format check, mypy.
2. **test** — Installs only `src/services/api/requirements.txt`. Runs `pytest -v`.

Both jobs run on `ubuntu-latest` with Python 3.12.

NOTE: a PR that modifies `.github/workflows/**` is held for maintainer approval by GitHub
before any job runs. It shows as `action_required` with zero jobs, which is a pending approval
rather than a pass — approve it from the Actions tab or with
`gh api -X POST repos/<owner>/<repo>/actions/runs/<id>/approve`.

NOTE: `tests/api/test_postprocessing.py` has 6 pre-existing failures unrelated to any launcher
work. Confirm the count against `origin/development` before blaming a change.

### `open-pr-to-development.yml`

Triggers: push to `feature/**`, `fix/**`, `bugfix/**`.

Queries existing open PRs from that branch to `development` via the GitHub API. If none found, creates one using the first line of the push commit as the title. Requires **Read and write permissions** in repo Settings → Actions → General → Workflow permissions.

### `main-pr-source.yml`

Triggers: PR targeting `main`.

Validates that `github.head_ref` is `development`. Exits with an error otherwise, blocking the PR merge. Intended to be configured as a required status check in branch protection rules for `main`.

## Docker image lifecycle

### Build context

All Dockerfiles use the **project root** as build context (set in `docker-compose.yml`). Paths in COPY instructions are relative to the project root.

### Images

| Service | Dockerfile | Base | Purpose |
|---------|-----------|------|---------|
| `api` | `src/services/api/Dockerfile` | `python:3.12-alpine` | FastAPI gateway. Includes `tests/` for in-container test runs. |
| `inference` | (external) | `ghcr.io/ggml-org/llama.cpp:server-cuda12-b9538` | llama.cpp server with GGUF models. |
| `inference-vllm` | `src/inference-vllm/Dockerfile` | `ubuntu:latest` | vLLM alternative (alternate-inference profile). |
| `llama-stack` | `src/llama-stack/Dockerfile` | `python:3` | Meta llama-model CLI for weight downloads. |
| `ollama-stack` | `src/ollama-stack/Dockerfile` | `ubuntu` | Ollama CLI alternative. |
| `opencode` | `src/opencode-stack/Dockerfile` | `ghcr.io/anomalyco/opencode` | OpenCode AI CLI. Mounts `${PWD}:/workspace` for directory-agnostic operation. |
| `claude` | `src/claude-stack/Dockerfile` | `alpine` | Claude Code CLI. |
| `cursor` | `src/cursor-stack/Dockerfile` | `debian:bookworm` | Cursor CLI. Debian, not Alpine: its bundled Node is glibc-linked. |
| `codex` | `src/codex-stack/Dockerfile` | `alpine` | Codex CLI. |
| `grok` | `src/grok-stack/Dockerfile` | `alpine` | Grok Build CLI. |

Each agent stack also has a `Dockerfile_privileged` — identical except `USER root`.

### Build

```
make build
```

Builds `stack` profile (api + inference) and `tools` profile (llama-stack, opencode). Does NOT build `alternate-inference` (vLLM) or `ollama-stack`.

Agent images build from their own compose file:

```
docker compose -f docker-compose-claude.yml --profile stack build claude
```

### `.dockerignore`

Excludes `__pycache__`, `.pytest_cache`, `*.pyc`, `.git`, `docs/`. Cannot COPY docs into any image.

## Compose profiles

| Profile | Services | Use case |
|---------|----------|----------|
| `stack` | inference + api + agent | Default dev stack |
| `tools` | llama-stack + agent | CLI tools: weight downloads, AI coding assistant |
| `alternate-inference` | inference-vllm | Swap llama.cpp for vLLM |
| `stack_privileged` | inference + api + `<agent>_privileged` | Agent with nested-Docker capability (full-isolation files only) |

Profiles are per compose file: `claude` exists in `docker-compose-claude.yml`, not in
`docker-compose.yml`. `stack_privileged` appears only in the `-full-isolation` files.

Usage:
```
docker compose --profile stack up
docker compose --profile tools run --rm llama-stack llama-model list
docker compose --profile stack run --rm opencode
docker compose -f docker-compose-claude.yml --profile stack run --rm claude
docker compose --profile alternate-inference up
```

## Compose volumes

| Volume | Type | Mount | Access |
|--------|------|-------|--------|
| `model_data` | bind (`./models/`) | `/models` on inference | read-only for inference |
| `training_data` | named volume | `/training` on api | read-write |
| `model_hf_data` | named volume | `/root/.cache/huggingface` | read-write |
| `<agent>_config` / `_data` / `_state` / `_cache` / `_home` | named volume | the agent's XDG dirs and dotdir | read-write |

`model_data` is a bind mount — it survives `docker compose down -v`. The rest are named
volumes — destroyed by `down -v`, which is why `restart.sh` runs `down` **without** `-v`.

The five per-agent volumes exist so credentials, session history and settings never collide
between agents; `model_data`, `model_hf_data` and `training_data` belong to the shared
inference stack and are not per-agent. See [agents.md](agents.md#state-is-per-agent).

## Helper scripts

| Script | Action | Destructive? |
|--------|--------|-------------|
| `restart.sh` | `down` then `up --force-recreate --build -d` | No — volumes preserved (auth, sessions, HF cache) |
| `launch-<agent>.sh` | `docker compose --profile stack run --rm <agent>` | No |
| `launch-fresh-<agent>.sh` | Builds the agent image if absent, then `docker run` standalone | No |
| `start.sh` | Dispatches on `--agent` and mode to the launcher above | No |
| `scripts/check-template-sync.sh` | Fails if shared template files differ between agents | No |
| `scripts/check-entrypoint-sync.sh` | Fails if the two entrypoint copies drifted | No |
| `Makefile` | build, test, up aliases | No |

`restart.sh` takes the agent's compose basename via an internal `--compose` flag, passed by
`start.sh`, so `--restart --agent cursor` restarts the Cursor stack.

## Deployment / operations

- **No cloud dependency** — all inference runs locally in Docker.
- **No prompts leave the host** — only `request_id`, `tags`, `truncated`, `pii_masked` metadata logged.
- **PII masking** applied before inference (Chilean RUT regex).
- **Response headers:** `X-Request-Id`, `X-Prompt-Truncated`, `X-Prompt-Pii-Masked`.
- **Model weights** (`.gguf`) are not in git — placed in `./models/` manually (see `docs/models/README.md`).

## Release process

1. Feature work merges to `development` via PR.
2. Release PR from `development` → `main`.
3. Annotated SemVer tag on `main` (`vMAJOR.MINOR.PATCH`).
4. Integration tag on `development` after feature merge (`vMAJOR.MINOR.PATCH-dev.N`).

CI triggers on push/PR to both branches. No CD/deploy pipeline — images are built locally.
