# Project settings reference

## `pyproject.toml` — Project metadata, ruff, pytest

**`[project]`**
| Setting | Value |
|---------|-------|
| `name` | `code-inference-ai` |
| `version` | `0.1.0` |
| `requires-python` | `>=3.12` |

**`[tool.ruff]`**
| Setting | Value |
|---------|-------|
| `target-version` | `py312` |
| `line-length` | `100` |

**`[tool.ruff.lint]`**
| Setting | Value |
|---------|-------|
| `select` | `E, F, I, N, W, UP, SIM` |

**`[tool.ruff.format]`**
| Setting | Value |
|---------|-------|
| `quote-style` | `single` |

**`[tool.pytest.ini_options]`**
| Setting | Value |
|---------|-------|
| `pythonpath` | `["src/services/api"]` |
| `testpaths` | `["tests"]` |

Dual with `pytest.ini` (root) — identical content. Kept for tools that only read `pyproject.toml`.

---

## `pytest.ini` (root) — Pytest config (CI + host runs)

| Setting | Value |
|---------|-------|
| `pythonpath` | `src/services/api` |
| `testpaths` | `tests` |

Makes `app.*` importable from `src/services/api`. Used by CI and when running pytest outside Docker.

---

## `src/services/api/pytest.ini` — Pytest config (in-container)

| Setting | Value |
|---------|-------|
| `pythonpath` | `.` |
| `testpaths` | `tests` |

Used inside the `api` container where the working directory is `/app` and `./app/` is the Python package. Overrides the root config.

---

## `dev-requirements.txt` — Dev tooling (not in production)

```
pre-commit==4.1.0
ruff==0.9.6
mypy==1.15.0
```

Installed by CI lint job and by developers for local pre-commit hooks.

---

## `src/services/api/requirements.txt` — API runtime dependencies

```
fastapi==0.115.6
uvicorn[standard]==0.34.0
httpx==0.28.1
pydantic-settings==2.7.0
slowapi==0.1.9
pytest==8.3.4
```

NOTE: `pytest` is a runtime dep because it's installed in the production image to support in-container test runs (`make test`). Only pinned versions, no ranges.

---

## `.pre-commit-config.yaml` — Pre-commit hooks

| Hook | Source | Notes |
|------|--------|-------|
| `trailing-whitespace` | `pre-commit-hooks` v5.0.0 | |
| `end-of-file-fixer` | `pre-commit-hooks` v5.0.0 | |
| `check-yaml` | `pre-commit-hooks` v5.0.0 | |
| `check-added-large-files` | `pre-commit-hooks` v5.0.0 | `--maxkb=500` |
| `ruff` | `ruff-pre-commit` v0.9.6 | runs with `--fix` |
| `ruff-format` | `ruff-pre-commit` v0.9.6 | |
| `mypy` | `mirrors-mypy` v1.15.0 | `--no-strict-optional --ignore-missing-imports`, additional deps: pydantic, httpx, fastapi, slowapi, pydantic-settings |

---

## `.env.example` / `.env` — Environment variables

| Variable | Default (example) | Actual (.env) | Purpose |
|----------|-------------------|---------------|---------|
| `MODEL_FILENAME` | `model.gguf` | `qwen2.5-coder-3b-instruct-q4_k_m.gguf` | GGUF file in `model_data` volume |
| `CONTEXT_SIZE` | `1024` | `16384` | llama.cpp context window |
| `MAX_TOKENS` | `256` | `256` | Max tokens for inference |
| `THREADS` | `2` | `2` | CPU threads for llama.cpp |
| `TOOLS` | (not in example) | `all` | llama.cpp tool support |
| `INFERENCE_URL` | `http://inference:8080` | `http://inference:8080` | API → inference URL |
| `RATE_LIMIT_PER_MINUTE` | `30` | `30` | Rate limit on `/v1/chat/completions` |
| `MAX_PROMPT_CHARS` | `8000` | `8000` | Char-level truncation threshold |
| `API_PORT` | `8000` | (not set, uses default) | Host port for API |

`.env` is gitignored; copy from `.env.example`.

---

## `.dockerignore` — Docker build context exclusion

```
__pycache__
.pytest_cache
*.pyc
.git
docs
```

NOTABLE: `docs/` is excluded — you cannot COPY docs into any Docker image. If you need docs available at runtime, restructure or serve externally.

---

## `.gitignore` — Git exclusion

```
.env
__pycache__/
*.py[cod]
.pytest_cache/
.mypy_cache/
.ruff_cache/
*.egg-info/
dist/
build/
*.gguf
*.bin
docs/models/*.gguf
!docs/models/README.md
models/*
!models/README.md
opencode.json
```

NOTABLE: `opencode.json` is gitignored (local OpenCode config). `models/*` and `*.gguf` are excluded (large weights). But `docs/models/README.md` and `models/README.md` are force-included.

---

## `docker-compose.yml` — Service orchestration

**Build context:** `.` (project root) for all services.

**Services:**

| Service | Container name | Profiles | Build/Image |
|---------|---------------|----------|-------------|
| `inference-vllm` | `inference-vllm` | `alternate-inference` | `src/inference-vllm/Dockerfile` — **incomplete, do not use** |
| `inference` | `llama-inference` | `stack`, `inference` | `ghcr.io/ggml-org/llama.cpp:server-cuda12-b9538` — **only production-ready backend** |
| `api` | `llama-api` | `stack` | `src/services/api/Dockerfile` |
| `opencode` | `opencode` | `tools` | `src/opencode-stack/Dockerfile` — mounts `${PWD}:/workspace` |

**Networks:** `internal` (bridge) — shared by `inference`, `api`, and `opencode`. `inference-vllm` is NOT on this network (incomplete — cannot communicate with the API).

**Inference backends:** Only `inference` (llama.cpp) is production-ready. The `alternate-inference` profile exists as a placeholder for future backend swaps (vllm, ollama, etc.) but is not wired to the API — `INFERENCE_URL` always points to `http://inference:8080`. The `src/inference-vllm/`, `src/llama-stack/`, and `src/ollama-stack/` Dockerfiles are experimental stubs.

**Volumes:**
| Volume | Driver | Source | Mount |
|--------|--------|--------|-------|
| `model_data` | local bind | `./models` | `/models:ro` on inference |
| `training_data` | local (auto) | named volume | `/training:rw` on api |

**inference container** defaults from environment:
| Flag | Value |
|------|-------|
| `-m` | `/models/${MODEL_FILENAME:-model.gguf}` |
| `--host` | `0.0.0.0` |
| `--port` | `8080` |
| `--ctx-size` | `${CONTEXT_SIZE:-16384}` |
| `--threads` | `${THREADS:-6}` |
| `--jinja` | enabled |
| `--tools` | `${TOOLS:-all}` |

NOTE: The default `CONTEXT_SIZE` in `docker-compose.yml` is `16384` (different from `.env.example`'s `1024`). The `.env` sets it to `16384` and `.env.example` has `1024`.

**api container** environment:
| Variable | Default |
|----------|---------|
| `INFERENCE_URL` | `http://inference:8080` |
| `RATE_LIMIT_PER_MINUTE` | `30` |
| `MAX_PROMPT_CHARS` | `8000` |

### Request flow (stack profile)

Every chat completion follows a three-hop chain through the `internal` network:

```
opencode                  llama-api                  llama-inference
  │                          │                           │
  │ POST /v1/chat/completions│                           │
  │ baseURL: http://api:8000 │                           │
  │─────────────────────────►│                           │
  │                          │                           │
  │                  1. Parse request, validate           │
  │                  2. process_messages() —              │
  │                     RUT mask, truncate, tag          │
  │                  3. Build forward dict                │
  │                          │                           │
  │                          │  POST /v1/chat/completions │
  │                          │  inference_url:            │
  │                          │  http://inference:8080     │
  │                          │──────────────────────────►│
  │                          │                           │
  │                          │                  1. Load GGUF from
  │                          │                     /models/${MODEL_FILENAME}
  │                          │                  2. Run inference
  │                          │                     (--ctx-size, --threads)
  │                          │                  3. Return OpenAI-compatible response
  │                          │                           │
  │                          │◄──────────────────────────│
  │                          │                           │
  │                  4. Apply rate limit (slowapi)
  │                  5. postprocess_response() —          │
  │                     detect tool calls, validate,      │
  │                     convert to OpenAI format          │
  │                  6. Log metadata (no prompts)
  │                  7. Add X-Request-Id,
  │                     X-Prompt-Truncated,
  │                     X-Prompt-Pii-Masked headers
  │◄─────────────────────────┤                           │
```

**Key details per hop:**

| Hop | From | To | URL | Port |
|-----|------|----|-----|------|
| 1 | opencode | llama-api | `http://api:8000/v1/chat/completions` | 8000 |
| 2 | llama-api | llama-inference | `http://inference:8080/v1/chat/completions` | 8080 |
| 3 | llama-inference | model file | `/models/${MODEL_FILENAME:-model.gguf}` | — |

**What the API adds** (hop 2 intercepts and enriches):
- Chilean RUT masking via regex
- Char-level truncation on last user message
- Intent tagging from `X-code_inference-Intent` header
- Rate limiting (`RATE_LIMIT_PER_MINUTE`)
- Request ID and metadata headers on the response
- Parameter passthrough: `max_tokens`, `temperature`, `top_p`, `frequency_penalty`, `presence_penalty`, `seed`, `stop`, plus any extras (`tools`, `tool_choice`, etc.)
- Streaming passthrough (SSE) when `stream: true`
- **Post-processing of inference responses** — detects raw tool call JSON in model output and converts to OpenAI-compatible `tool_calls` format (see [Post-processing](#post-processing-responsepy))
- Retry with backoff on connect/timeout errors (3 attempts)
- Startup wait: polls inference `/v1/models` for up to 60s before accepting requests

---

### Post-processing (`postprocessing.py`)

**File:** `src/services/api/app/postprocessing.py`

**Purpose:** Bridges the gap between how local models output tool calls and what the OpenAI SDK (`@ai-sdk/openai-compatible`) expects.

#### Why it exists

Many local LLMs (via llama.cpp) output tool calls as **raw JSON text** in the assistant's `content` field — often wrapped in markdown code fences:

```
```json
{"name": "read_file", "arguments": {"path": "index.html"}}
```
```

The OpenAI API specification requires tool calls to be returned as a structured `tool_calls` array in the message object. The `@ai-sdk/openai-compatible` SDK used by opencode expects this format. Without post-processing, opencode would see the JSON as a plain text response and never execute the tool.

#### How it works

**1. `parse_tool_call(content)`** — Detects tool call JSON in assistant message content:
   - Strips markdown code fences (` ```json ... ``` `, ` ``` ... ``` `)
   - Parses the remaining text as JSON
   - Validates the structure has `name` (str) and `arguments` (dict or str)
   - Returns the parsed tool call or `None`

**2. `make_tool_call(tc)`** — Wraps a parsed tool call into OpenAI format:
   ```python
   {
     "id": "call_<random>",
     "type": "function",
     "function": {"name": "...", "arguments": "..."}
   }
   ```

**3. `_get_tool_names(tools)`** — Extracts allowed function names from the request's `tools` array. Used for validation to prevent hallucinated tool calls.

**4. `postprocess_nonstreaming(body, tools=None)`** — For non-streaming responses:
   - Extracts `tools` from the original request to get allowed function names
   - If `tools` is `None` or empty → passes through unchanged (no tools expected)
   - Runs `parse_tool_call` on `choices[0].message.content`
   - If a tool call is detected **and** its `name` is in the allowed set → rewrites the message with `tool_calls`, sets `finish_reason` to `"tool_calls"`
   - If `name` is NOT in the allowed set → passes through as text (hallucination rejected)
   - Normal text responses are never affected

**5. `postprocess_streaming(raw_gen, tools=None)`** — For streaming (SSE) responses:
   - Buffers all SSE chunks from llama.cpp
   - Reconstructs the full assistant content from `delta.content` across all events
   - If no `tools` defined → passes through as-is
   - If tool call detected and name is valid → emits properly formatted `tool_calls` SSE deltas:
     1. Skeleton: `{"role":"assistant","tool_calls":[{"id":"call_...","function":{"name":"...","arguments":""}}]}`
     2. Arguments streamed as incremental JSON string chunks
     3. Finish: `{"finish_reason":"tool_calls"}`
     4. `data: [DONE]`
   - Handles non-SSE fallback: if llama.cpp returns a plain JSON response, it wraps it via `postprocess_nonstreaming` into a single SSE event

#### Validation against hallucinated tool calls

Some local models generate tool call JSON even when the user just says "hello". The `tools` parameter from the request acts as an allowlist:

| `tools` in request | Name matches | Behavior |
|--------------------|--------------|----------|
| Not present | — | No conversion (pass through as text) |
| Present | ✅ In allowlist | Convert to `tool_calls` |
| Present | ❌ Not in allowlist | Treat as normal text (reject hallucination) |

This ensures only **intended tool calls** are ever executed, regardless of which model is running or how it formats its output.

---

## `src/services/api/Dockerfile` — API image

| Setting | Value |
|---------|-------|
| Base | `python:3.12-alpine3.21` |
| Workdir | `/app` |
| System deps | `ca-certificates` |
| CMD | `uvicorn app.main:app --host 0.0.0.0 --port 8000` |
| Port | `8000` |

Two-phase COPY: first `requirements.txt` + `pytest.ini` for layer caching, then `app/` and `tests/`.

---

## `src/inference-vllm/Dockerfile` — vLLM alternative

| Setting | Value |
|---------|-------|
| Base | `ubuntu:latest` |
| System deps | `python3, python3-pip, curl` |
| CMD | `vllm serve Qwen/Qwen3-Coder-Next` |
| Volume | `/models` |

Unpinned base image (`ubuntu:latest`).

---

## `src/llama-stack/Dockerfile` — Meta CLI for weight downloads

| Setting | Value |
|---------|-------|
| Base | `python:3` |
| Pip | `llama-stack llama-models` |
| CMD | `llama-model --help` |
| Volume | `/models` |

Entrypoint is empty (`ENTRYPOINT []`) so arbitrary commands can be passed.

---

## `src/ollama-stack/Dockerfile` — Ollama CLI

| Setting | Value |
|---------|-------|
| Base | `ubuntu` |
| System deps | `curl, zstd` |
| Install | curl-piped `ollama.com/install.sh` |
| CMD | `ollama --help` |
| Volume | `/models` |

Unpinned base image (`ubuntu`). Installs via shell pipe — security note for production.

---

## `src/opencode-stack/Dockerfile` — OpenCode CLI

| Setting | Value |
|---------|-------|
| Base | `ghcr.io/anomalyco/opencode:2.0.22` |
| Adds | `git` (apk) |
| User | `opencode` (non-root, created with home) |
| Workdir | `/workspace` |

Also creates XDG base directories (`~/.config/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`, `~/.cache/opencode`) with `opencode` ownership so volumes mount correctly when empty.

The compose service mounts `${PWD}:/workspace` and uses `stdin_open: true` + `tty: true` for interactive sessions. See `docs/opencode-stack.md` for full details.

Usage:
```
# From this repo (uses launch-opencode.sh wrapper):
./launch-opencode.sh

# From any directory with this compose file available:
docker compose --profile tools run --rm opencode

# Without compose file (no persistent volumes):
docker run -it --rm -v "$(pwd)":/workspace ghcr.io/anomalyco/opencode:2.0.22
```

---

## `.github/workflows/ci.yml` — CI pipeline

| Setting | Value |
|---------|-------|
| Triggers | Push/PR to `main`, `development` |
| Python | `3.12` |
| Runner | `ubuntu-latest` |

**lint job:** Installs `src/services/api/requirements.txt` + `dev-requirements.txt`. Runs `ruff check`, `ruff format --check .`, `mypy src/`.

**test job:** Installs only `src/services/api/requirements.txt`. Runs `pytest -v`.

---

## `Makefile` — Convenience aliases

| Target | Command | Profiles |
|--------|---------|----------|
| `build` | `docker compose build --profile stack --profile tools` | stack, tools |
| `test` | `docker compose --profile stack run --rm --no-deps api pytest -v` | stack |
| `up` | `docker compose --profile stack up --build` | stack |

NOTE: `make build` now also builds the `opencode` service (tools profile), which pulls/updates the `ghcr.io/anomalyco/opencode` image.

---

## `opencode.json` / `opencode.json.example` — OpenCode (AI agent) config

The actual `opencode.json` is gitignored (local override). `opencode.json.example` is committed as a template.

**Actual (`opencode.json`):**
```
provider: code-inference (npm @ai-sdk/openai-compatible)
model:    qwen2.5-coder-3b-instruct-q4_k_m.gguf
  name:           Qwen 2.5 Coder 3B
  supportsToolCalls: true
  context limit:  65536
  output limit:   32768
baseURL:  http://localhost:8080/v1
instructions: [AGENTS.md, .opencode/instructions/git-workflow.md]
```

**Example (`opencode.json.example`):**
```
provider: code-inference (npm @ai-sdk/openai-compatible)
model:    model.gguf
  name:           Meta Llama 3 1B Instruct
  contextWindow:  4096
baseURL:  http://localhost:8080/v1
```

---

## `AGENTS.md` — AI agent workspace instructions

Loaded by `opencode.json` as agent instructions. Contains commands, architecture, code style, setup, testing quirks, CI info, and gotchas.

---

## `.opencode/instructions/git-workflow.md` — AI agent git rules

Loaded by `opencode.json` as an agent instruction. Always applied. Enforces:
- Topic branches from `development`, PR to `development`, release to `main`
- No rebase
- Keep merged branches
- Annotated SemVer tags
- Sync-git workflow
