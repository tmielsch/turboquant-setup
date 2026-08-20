# Mac Setup: llama-swap + mlx-lm on Apple Silicon

Run small-to-medium Qwen / Gemma models on a **Mac with Apple Silicon**
(tested on a MacBook Air M2, 24 GB unified memory), served through a single
OpenAI-compatible API endpoint — same architecture as the PC Docker setup,
but natively on macOS.

- One gateway endpoint (`http://127.0.0.1:8080/v1`), **one model loaded at a
  time**, hot-swapped on demand when a client requests a different model ID
- Backend: **MLX** (`mlx_lm.server`), the fast native inference stack for
  Apple Silicon (~2x faster than llama.cpp-Metal), not the CUDA-only
  TurboQuant engine
- Model profiles with individual context windows (32K / 64K / 128K), so you
  can pick the right model+context combo per sub-agent task
- Auto-start via launchd — no Docker, no scripts scattered around the system

## Why not Docker on macOS?

Docker Desktop / OrbStack run containers in a Linux VM, and **Metal does not
run inside Linux containers** (Apple closed the GPU-in-container feature
request as "won't fix"). GPU inference through Docker on a Mac falls back to
CPU and is 3-5x slower. Workarounds (krunkit/Vulkan, vsock daemons) are
experimental and not worth it. Native processes are the correct approach on
macOS — and llama-swap manages those for you, so it still *feels* like the
container setup.

## Architecture

```
Hermes / OpenCode / any OpenAI-compatible client
                 |
                 |  http://127.0.0.1:8080/v1
                 v
            llama-swap (gateway, Go binary)
                 |
                 |  requested model ID
                 v
       mlx_lm.server (started on demand, fp16 KV)
                 |
                 +-- MLX weights from Hugging Face cache
                 +-- context / KV runtime profile
```

llama-swap runs **one backend at a time** by default: requesting a different
model ID stops the running `mlx_lm.server` process and starts the matching
one. First request to a model has a cold start of 5-30 s (model load), every
request after that runs at full speed. Optionally add a `globalTTL` so idle
models are unloaded from memory.

## Requirements

- Apple Silicon Mac (M1 or newer; M2 tested), **24 GB unified memory**
  recommended (~18 GB usable for models)
- macOS 14+
- [Homebrew](https://brew.sh)
- [uv](https://docs.astral.sh/uv/) (for installing `mlx-lm`)
- ~15 GB free disk space for the models

## 1. Install mlx-lm

```bash
uv tool install mlx-lm
```

Check the available server flags (used in step 4):

```bash
mlx_lm.server --help
```

> Note: flag names vary between mlx-lm versions. Newer versions use
> `--context-length` to cap the context window; if yours does not, check for
> `--max-kv-size` instead. The commands below use `--context-length`.

## 2. Models (MLX 4-bit)

| Model | HF repo | Size | Notes |
|---|---|---|---|
| Qwen3.5 9B | `mlx-community/Qwen3.5-9B-MLX-4bit` | ~6 GB | Main model for coding sub-agents |
| Qwen3.5 4B | `mlx-community/Qwen3.5-4B-MLX-4bit` | ~2.7 GB | Bulk research / small agents (check exact repo name on HF) |
| Gemma 4 E4B | `deadbydawn101/gemma-4-E4B-mlx-4bit` | ~5 GB | Community port, experimental |

`mlx_lm.server` downloads a model from Hugging Face into its cache
automatically on first start — no manual download needed. If you prefer to
prefetch:

```bash
uv run huggingface-cli download mlx-community/Qwen3.5-9B-MLX-4bit
```

## 3. Install llama-swap

```bash
brew tap mostlygeek/llama-swap
brew install llama-swap
```

## 4. Gateway configuration

Create `~/.config/llama-swap/config.yaml`:

```yaml
# One backend loaded at a time; cold start on model switch.
startPort: 5800
sendLoadingState: false
# Unload a model 10 minutes after the last request (0 = keep loaded forever).
globalTTL: 600

models:
  "mac-research-4b":
    name: "Qwen3.5 4B - 128K research"
    description: "Bulk research / small sub-agents, maximum context."
    cmd: |
      mlx_lm.server --model mlx-community/Qwen3.5-4B-MLX-4bit
      --host 127.0.0.1 --port ${PORT} --context-length 131072
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 131072
  "mac-code-9b-32k":
    name: "Qwen3.5 9B - 32K fast coding"
    description: "Fast coding agents, small context."
    cmd: |
      mlx_lm.server --model mlx-community/Qwen3.5-9B-MLX-4bit
      --host 127.0.0.1 --port ${PORT} --context-length 32768
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 32768
  "mac-code-9b-64k":
    name: "Qwen3.5 9B - 64K coding"
    description: "Coding agents with large file context."
    cmd: |
      mlx_lm.server --model mlx-community/Qwen3.5-9B-MLX-4bit
      --host 127.0.0.1 --port ${PORT} --context-length 65536
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 65536
  "mac-gemma-e4b":
    name: "Gemma 4 E4B - experimental"
    description: "Gemma 4 E4B (community MLX port), 64K context."
    cmd: |
      mlx_lm.server --model deadbydawn101/gemma-4-E4B-mlx-4bit
      --host 127.0.0.1 --port ${PORT} --context-length 65536
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 65536
```

### Memory budget (24 GB machine, fp16 KV)

| Model profile | Weights | KV at context | Total |
|---|---|---|---|
| Qwen3.5 4B @ 128K | ~2.7 GB | ~9.4 GB | ~12 GB |
| Qwen3.5 9B @ 32K | ~6 GB | ~2.7 GB | ~9 GB |
| Qwen3.5 9B @ 64K | ~6 GB | ~5.4 GB | ~11.5 GB |
| Gemma 4 E4B @ 64K | ~5 GB | model-dependent | ~10-13 GB |

All profiles fit the ~18 GB you get on a 24 GB Mac (macOS uses the rest).
Larger contexts on the 9B (e.g. 128K) still fit as a single model, but only
with no headroom for other apps.

## 5. Start the gateway and enable auto-start

Test manually first (config flag may be `-config` depending on version —
check `llama-swap --help`):

```bash
llama-swap --config ~/.config/llama-swap/config.yaml
```

Auto-start via a launchd LaunchAgent (equivalent to `restart: unless-stopped`).
Create `~/Library/LaunchAgents/com.mostlygeek.llama-swap.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.mostlygeek.llama-swap</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/llama-swap</string>
    <string>--config</string>
    <string>/Users/YOURUSER/.config/llama-swap/config.yaml</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/llama-swap.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/llama-swap.err</string>
</dict>
</plist>
```

Then:

```bash
launchctl load ~/Library/LaunchAgents/com.mostlygeek.llama-swap.plist
```

No model is loaded at startup — the first API request for a model ID starts
the matching backend.

## 6. Verify

```bash
curl http://127.0.0.1:8080/v1/models

curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"mac-code-9b-32k","messages":[{"role":"user","content":"Hello!"}]}'
```

Web UI: `http://127.0.0.1:8080/ui` — shows the loaded model, request log and
per-model stats.

## 7. OpenCode integration

Add a provider for the gateway (same pattern as the PC setup, different base
URL and model IDs). Example `opencode.json`:

```json
{
  "provider": {
    "mac": {
      "npm": "@ai-sdk/openai-compatible",
      "baseURL": "http://127.0.0.1:8080/v1",
      "apiKey": "local",
      "models": {
        "mac-research-4b": { "context_length": 131072 },
        "mac-code-9b-32k": { "context_length": 32768 },
        "mac-code-9b-64k": { "context_length": 65536 },
        "mac-gemma-e4b":  { "context_length": 65536 }
      }
    }
  }
}
```

### Sub-agent profiles

Pick one profile per sub-agent role — llama-swap swaps the model on demand
when you switch, so only one model occupies memory at a time:

| Task | Model ID |
|---|---|
| Bulk research, summarization, many parallel agents | `mac-research-4b` (128K) |
| Coding agents, normal file context | `mac-code-9b-64k` |
| Fast smoke tests / tiny tasks | `mac-code-9b-32k` |
| Language-heavy writing (Gemma style) | `mac-gemma-e4b` |

## KV cache: do NOT use `--kv-bits` on MLX

MLX's KV quantization (`--kv-bits 4|8`) sounds like a free context upgrade but
measured measurements show the opposite on this stack:

- Quantized KV cannot use MLX's fused attention kernel and instead
  materializes the full query-key score matrix — **peak memory rises** with
  context instead of falling (4-bit OOMs at 32K where fp16 fits at 9.4 GB on
  a 16 GB Mac, same shape on Qwen3-4B)
- 8-bit KV decoded **~4x slower** than fp16 in those measurements
- Models with a rotating/sliding-window KV cache (Gemma 3/4 style) reject KV
  quantization outright: `NotImplementedError: RotatingKVCache Quantization NYI`

**Conclusion: keep the default fp16 KV cache and size the context window
accordingly** (see the memory table above). Source:
<https://prasadkhake.com/blog/kv-bits-memory-flag-backfires>

## Troubleshooting

### Cold start on every model switch is slow

Normal: llama-swap unloads the old model and loads the new one (5-30 s,
model load from disk). Raise `globalTTL` if you switch back and forth a lot.

### Model does not fit / macOS says low memory

Reduce the context length of the profile (KV is the largest variable), or
use the 4B model. On a 24 GB Mac, one 9B profile at 64K leaves comfortable
headroom.

### Gemma 4 profile errors on start

The Gemma 4 MLX port is community-maintained. If `mlx_lm.server` fails to
load it, check the model repo page for the required mlx-lm version, or drop
the profile — Qwen 4B is the stable fallback.

### Gateway starts, but `/v1/models` returns nothing

Check the config file location (llama-swap reads `config.yaml` from the
current directory unless `--config` is given) and the log at
`/tmp/llama-swap.err`.

## See also

- [README.md](../README.md) — PC setup (Docker + TurboQuant CUDA)
- [MODELS.md](MODELS.md) — model registry and KV cache options
- [llama-swap](https://github.com/mostlygeek/llama-swap) — gateway
- [mlx-lm](https://github.com/ml-explore/mlx-lm) — MLX inference stack
