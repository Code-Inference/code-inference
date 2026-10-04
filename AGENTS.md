# code-inference-ai

Local inference stack. FastAPI gateway proxies to llama.cpp; all inference stays on-host. PII masking (Chilean RUT), char-level truncation, intent tagging.

Git workflow: see `.opencode/instructions/git-workflow.md` (loaded via `opencode.json` instruction). Comprehensive config reference: `docs/settings.md`.

## Docker commands

| Action | Command |
|--------|---------|
| Build stack + tools images | `make build` |
| Run stack (always rebuilds) | `make up` |
| Unit tests (no inference needed) | `make test` |
| Single test | `docker compose --profile stack run --rm --no-deps api pytest -v tests/api/test_prompt.py::TEST_NAME` |
| Shell into API container | `docker compose --profile stack run --rm api sh` |
| Full restart (preserves volumes) | `code-inference --restart` |

## Host commands (CI / pre-commit)

| Action | Command |
|--------|---------|
| Ruff lint | `ruff check .` |
| Ruff format check | `ruff format --check .` |
| mypy | `mypy --config-file=pyproject.toml --no-strict-optional --ignore-missing-imports src/` |
| Pre-commit | `pre-commit run --all-files` |

## Architecture

- **Entrypoint:** `src/services/api/app/main.py:22` — FastAPI app. Routes: `GET /health`, `GET /health/ready` (pings inference `/v1/models`), `POST /v1/chat/completions` (proxies after prompt processing).
- **Request flow:** opencode → api (RUT mask, truncate, tag) → inference (llama.cpp). Three-hop chain on `internal` network.
- **Compose profiles:** `stack` (inference+api, default), `tools` (opencode CLI), `alternate-inference` (vLLM, **not wired** to `internal` network).
- **Only inference (llama.cpp) is production-ready.** Other backends (vllm, ollama) are experimental stubs.
- **Prompt processing:** `src/services/api/app/prompt.py` — RUT masking via regex `_RUT_RE`, char-level truncation (last user message only, appends `…[truncated]`), intent tagging.
- **No raw prompts logged** — only `request_id`, `tags`, `truncated`, `pii_masked` flags. Response headers: `X-Request-Id`, `X-Prompt-Truncated`, `X-Prompt-Pii-Masked`.
- **Config:** `src/services/api/app/config.py` — pydantic-settings reads `.env` at module level (singleton).

## Code style

- Ruff: line-length 100, target py312, lint `E,F,I,N,W,UP,SIM`, **single quotes**.
- mypy: `--no-strict-optional --ignore-missing-imports`.

## Setup

1. `cp .env.example .env`, adjust vars (see `docs/settings.md` for full reference).
2. Place a GGUF model in `./models/` (see `docs/models/README.md`).
3. `make build && make up`.

## Testing quirks

- **Unit tests only** (no inference container). Single file: `tests/api/test_prompt.py` (3 tests).
- **`pytest` is a runtime dep** in `src/services/api/requirements.txt` — intentional for in-container `make test`.
- **Dual pytest configs:** root `pyproject.toml`/`pytest.ini` set `pythonpath=src/services/api` (CI/host). Container `src/services/api/pytest.ini` sets `pythonpath=.` (workdir `/app`). New tests go in `tests/api/`.

## CI

- Triggers: push/PR to `main` or `development`.
- **lint job:** installs `requirements.txt` + `dev-requirements.txt`, runs `ruff check`, `ruff format --check .`, `mypy src/`.
- **test job:** installs only `requirements.txt`, runs `pytest -v`.

## Gotchas

- **`opencode.json` is gitignored** — `templates/opencode-default/opencode.json` is the committed template. Actual config loads `AGENTS.md` + `.opencode/instructions/git-workflow.md`.
- **`templates/<agent>-default/`** bootstraps new projects via `start.sh` (copies `opencode.json`, `AGENTS.md`, git workflow, CI workflows).
- **`.dockerignore` excludes `docs/`** — cannot COPY docs into any image.
- **`code-inference --restart`** uses `down` **without** `-v`, so all volumes survive: `opencode_config` (auth tokens), `opencode_data` (sessions), `model_hf_data` (HF cache, ~540MB), `training_data`. It exits non-zero if `./models/` is empty. `--purge` is the only way to destroy volumes, and it confirms first. Accepts the same stack flags as the launcher (`--full-isolation`, `--disk-name`, `--privileged`) so it restarts the stack you actually use.
- **`restart.sh` does not pass `-f`/`-p` beyond its own flags**; it derives the project from `basename "$PWD"` like the launcher. Run it from your project directory.
- **`make build`** builds both `stack` and `tools` profiles (pulls `ghcr.io/anomalyco/opencode`).
- **`make up`** always runs `--build` (picks up local code changes).
- **`CONTEXT_SIZE`:** `.env.example` defaults to 1024; compose shell default is 16384; `.env` sets 16384. Verify your actual value.
- **`TOOLS` env var:** `.env.example` omits it; compose default is `all`; `.env` sets `TOOLS=all`.
- **`inference-vllm`** is on `alternate-inference` profile, NOT on `internal` network — cannot reach API.
- **Default branch:** `development`. Gitflow + SemVer. No rebase. Keep merged topic branches.
- **`models/*` and `*.gguf` gitignored** — do not commit weights.
- **SSH config workaround (macOS host):** `~/.ssh/config` may contain `UseKeychain yes` (macOS-only). This is invalid on Linux and causes SSH to abort. `entrypoint.sh` strips it and sets `GIT_SSH_COMMAND`. Container's compose service already sets `GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=accept-new`.
- **Temp SSH dir for known_hosts and keys:** `~/.ssh` is a Docker ro bind-mount — the container cannot write to it or change its permissions. `entrypoint.sh` section 2 copies any existing SSH files into a temp dir (`/tmp/ssh-keyscan-*`) and writes `github.com`'s host key there, then sets `GIT_SSH_COMMAND` with `-o UserKnownHostsFile=` pointing at the temp file. The temp dir is cleaned up on exit via `ssh_cleanup` trap. This avoids failures from trying to write `known_hosts` (or generate new keys in the `gh auth` block) on a ro filesystem.
- **`entrypoint.sh`** (`src/opencode-stack/entrypoint.sh`) is the Docker `ENTRYPOINT` for the opencode service. Runs on container start: sets up `.profile`, `gh auth`, git identity, then `exec opencode "$@"`. Interactive prompts (`gh auth`, git config) skip when not a TTY. Idempotent — skips configured steps.
- **Two entrypoint copies, on purpose (transition).** `src/common/entrypoint.sh` is shared by the claude, codex, cursor and grok stacks and ends in `exec "${AGENT_BIN:-opencode}" "$@"`. `src/opencode-stack/entrypoint.sh` is the pre-split copy, kept so the opencode image builds and behaves exactly as before. They differ **only** in the header comment and that exec line — `AGENT_BIN` is unset in the opencode stack, so both run the same command. **Apply any logic change to both files**, or run `./scripts/check-entrypoint-sync.sh` (pre-commit + CI) to catch a one-sided edit. Delete the opencode-stack copy once that stack adopts the shared one.
- **CLI wrapper chain:** `install.sh` → `start.sh` → `launch-opencode.sh`/`launch-fresh-opencode.sh`. Installs to `~/.code-inference`, creates `code-inference` bin command.
- **Cross-references that don't exist on disk:** `docs/architecture.md`, `docs/rate-limits.md`, `docs/git-workflow.md`.
