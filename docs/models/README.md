# Model weights (GGUF)

Place a **Llama 3.2** (or compatible) **GGUF** checkpoint in the Docker **model_data** volume as the file name configured by `MODEL_FILENAME` (default: `model.gguf`).

## Where to get a `.gguf` file

Weights are **not** in this repository (large files; see `.gitignore`).

- **Hugging Face** is the usual place to download a **`.gguf`** build: search for the model family you want (e.g. Llama 3.2) and **GGUF**, open the model page, use the **Files** tab, and download a **`.gguf`** artifact. For gated Meta models you must **log in** and **accept the license** on that page before downloading.
- **Meta** is the **licensor** of Llama; official distribution for developers often goes **through Hugging Face** (e.g. under the `meta-llama` organization). Meta does not always ship a ready-made **`.gguf`** on a separate “Meta-only” download page — **GGUF** is produced for **llama.cpp** and is commonly published on HF by Meta or by reputable conversion/quantization repos.

## Verifying downloads (supply chain hygiene)

- **Prefer official or well-known publishers** on Hugging Face (e.g. `meta-llama` for Llama, or established GGUF mirrors with clear provenance and many downloads). Avoid unknown mirrors or “one-click” sites.
- **Download from the real model URL** on **`huggingface.co`** (browser or `huggingface-cli`), not untrusted pasted links.
- **Check the artifact**: you want a **`.gguf`** file of **roughly the size** described on the model card for that quantization (e.g. Q4). A “model” that is only a few kilobytes is not a real checkpoint.
- **Checksums**: if the publisher lists **SHA256**, verify after download (e.g. `shasum -a 256 your-model.gguf` on macOS) and compare.
- **Do not run** random scripts or installers bundled alongside weights unless you trust the publisher; for this stack you only need the **`.gguf`** in the volume.
- **Risk in context**: a `.gguf` is **data** consumed by `llama.cpp`, not a macOS app you execute by double-clicking. The usual risks are **wrong/broken files**, **phishing / fake download pages**, or **trusting the wrong repo** — the same hygiene as any large download from the internet.

## Meta `llama-model` CLI (Docker, no host install)

The **`llama-stack`** image (Compose **profile `tools`**) installs Meta’s **`llama-models`** CLI. It mounts the same **`model_data`** volume at **`/models`** read-write so downloads land next to what **inference** reads (read-only).

```bash
docker compose --profile tools build llama-stack
docker compose --profile tools run --rm llama-stack llama-model list
docker compose --profile tools run --rm -it llama-stack llama-model download --source meta --model-id <MODEL_ID>
```

Use **`-it`** for `download` when the CLI prompts for a signed URL or other input.

Use the **signed URL** from Meta when prompted. Outputs are usually **not** GGUF; convert or add a **`.gguf`** for `llama.cpp` as described above.

## Example: copy into the volume

After the stack has been created once:

```bash
docker run --rm -v code-inference-ai_model_data:/models -v "$PWD:/host" alpine \
  cp /host/your-model.gguf /models/model.gguf
```

(Adjust the volume name prefix if your project directory name differs; use `docker volume ls` to find it.)

The **inference** service mounts `/models` read-only and passes `-m /models/model.gguf` to `llama-server` by default.

Do **not** commit `.gguf` files to git (see `.gitignore`).

To quickly restart the stack, run the following script:

```bash
code-inference --restart
```

It preserves all volumes, so stored auth, session history, and the HuggingFace cache survive the restart. It exits non-zero if `./models/` is empty. Pass `--purge` to discard volumes (with confirmation), and `-y` to skip that confirmation.

To download a model that works, run the following command:

```bash
curl -L "https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf" -o ./models/Meta-Llama-3-1B-Instruct-Q4_K_M.gguf
```

curl -L https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf -o ./models/qwen2.5-coder-3b-instruct-q4_k_m.gguf

## Tool calling

### The bottleneck is the model

Tool calling reliability depends on **model size**, not configuration. Small models (≤3B) don't have enough capacity to understand *when* to use tools vs *when* to chat. They see tool definitions and try to use them for everything — including "hello."

Our default model is **Qwen 2.5 Coder 3B Q4_K_M** (~3B parameters, heavily quantized). It produces hallucinated tool calls like `{"name":"read_file","arguments":{...}}` on simple chat when tool definitions are present. This is **expected behavior** for a model this size, not a configuration or server issue.

### Model comparison

| Model | Size | Q4_K_M on disk | Min RAM | OS | Tool calling |
|-------|------|----------------|---------|-----|-------------|
| Qwen 2.5 Coder 3B | 3B | ~2 GB | 4 GB | macOS, Linux, Windows | 🟡 Unreliable, hallucinates often |
| Qwen 2.5 Coder 7B | 7B | ~4.5 GB | 8 GB (16 GB comfortable) | macOS (M1+), Linux, Windows | 🟢 Good |
| Qwen 2.5 Coder 14B | 14B | ~8.5 GB | 16 GB (32 GB comfortable) | macOS (M1 Pro+), Linux | 🟢 Great |
| DeepSeek Coder 6.7B | 6.7B | ~4 GB | 8 GB (16 GB comfortable) | macOS (M1+), Linux, Windows | 🟢 Good |
| Llama 3.1 8B | 8B | ~4.5 GB | 8 GB (16 GB comfortable) | macOS (M1+), Linux, Windows | 🟢 Good |

> **Apple Silicon note:** llama.cpp uses Metal GPU acceleration on macOS. M-series chips with unified memory are ideal — RAM is shared between CPU/GPU so model memory counts once. An M1 with 16 GB runs 7B models comfortably.

> **Intel Mac note:** Intel Macs lack Metal GPU acceleration for llama.cpp, falling back to CPU-only inference. This is significantly slower — expect 1–2 tok/s on 7B models vs 15–25 tok/s on M1. Stick with 3B models for usable speeds, or consider switching to an M-series machine.

### Expected performance by platform

Tokens per second (tok/s) for Q4_K_M quant at 2048 context, single user. Results vary with batch size, prompt length, and system load.

| Platform | LLM backend | 3B model | 7B model | 14B model | Verdict |
|----------|-------------|----------|----------|-----------|---------|
| Apple Silicon M1 8 GB | Metal GPU | 25–30 tok/s | 10–15 tok/s | ❌ OOM | Great for 3B, usable for 7B |
| Apple Silicon M1 16 GB | Metal GPU | 30–35 tok/s | 15–20 tok/s | 5–8 tok/s | Sweet spot for 7B |
| Apple Silicon M1 Pro/Max/Ultra | Metal GPU | 40–50 tok/s | 20–30 tok/s | 10–15 tok/s | Best Apple option |
| Apple Silicon M4 24 GB+ | Metal GPU | 50–60 tok/s | 30–40 tok/s | 15–20 tok/s | Best Apple option |
| Intel Mac (any) | CPU (no Metal) | 5–10 tok/s | 1–3 tok/s | ❌ too slow | Not recommended |
| Linux x86_64 (CPU, AVX2) | CPU (OpenBLAS) | 10–15 tok/s | 3–5 tok/s | ❌ too slow | Usable only for 3B |
| Linux + NVIDIA RTX 3060+ | cuBLAS GPU | 40–60 tok/s | 25–40 tok/s | 10–15 tok/s | Great value |
| Linux + NVIDIA RTX 4090 | cuBLAS GPU | 80–100 tok/s | 50–70 tok/s | 25–35 tok/s | Production-ready |
| Windows + NVIDIA (CUDA) | cuBLAS GPU | 40–60 tok/s | 25–40 tok/s | 10–15 tok/s | Great for 7B |
| Windows (CPU only) | CPU (AVX2) | 10–15 tok/s | 3–5 tok/s | ❌ too slow | Not recommended |

### Size guidelines

| Model size | Tool calling reliability | Recommended for |
|------------|------------------------|----------------|
| 1B–3B | 🟡 Unreliable, hallucinates often | Chat-only, no tools needed |
| 7B | 🟢 Good with occasional misses | Light tool use, dev work |
| 14B+ | 🟢 Reliable | Production tool calling |

What YouTubers run: almost always 7B+ models on multi-GPU setups or cloud instances. A "laptop demo" of tool calling typically uses a 7B model at Q4, or a smaller model that happens to handle the demo's specific use case.

### Architecture: how tools flow through the stack

```
opencode CLI                    API                          llama.cpp
  │                             │                             │
  │ POST with tools=[…]         │                             │
  │────────────────────────────►│                             │
  │                             │────────────────────────────►│  --tools all
  │                             │   forwards tools + messages │  processes tools
  │                             │                             │  via Jinja template
  │◄────────────────────────────│◄────────────────────────────│
  │   tool_calls (converted)    │   raw JSON in content       │
  │                             │   post-processor converts   │
```

- **opencode CLI** sends `tools` in requests → `--tools all` enables llama.cpp to process them → the model outputs tool call JSON → the API post-processor converts raw JSON to OpenAI `tool_calls` format
- **Web UI** does **not** send `tools` → the model sees no tool definitions → responds naturally without hallucination

The web UI intentionally omits `tools` from requests because small models hallucinate when they see tool definitions, and web UI cannot execute filesystem tools anyway.

### Backend portability

The `--tools all` flag is **llama.cpp-specific**. If swapping to ollama or vLLM:
- Remove `--tools all` from the inference service command
- The API's `postprocessing.py` handles tool call conversion uniformly regardless of backend
- The API's `prompt.py` would need tool-injection logic if the new backend doesn't process `tools` natively

### Real fix for better tool calling: upgrade the model

Download a 7B GGUF from Hugging Face:

```bash
curl -L -o ./models/qwen2.5-coder-7b-instruct-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
```

Then set `MODEL_FILENAME=qwen2.5-coder-7b-instruct-q4_k_m.gguf` in `.env` and restart.

See `docs/settings.md` for the full post-processing reference.