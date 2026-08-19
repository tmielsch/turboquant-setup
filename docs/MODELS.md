# Adding models

Every model served through the gateway is defined in **`models.conf`** at the
repository root. The Docker image is **never rebuilt** to add a model: the
generated llama-swap config is bind-mounted into the container, so adding a
model is just three steps:

```bash
# 1. Put the GGUF file into your models directory
#    (the directory configured as MODELS_DIR in .env, default: ./models)

# 2. Add an entry to models.conf (or run the interactive wizard)
bash scripts/add-model.sh

# 3. Regenerate + restart the gateway (takes seconds, no rebuild)
bash scripts/generate-config.sh
docker compose restart turboquant
```

## models.conf format

```ini
[global]
engine=/app/llama-server     # engine binary inside the container (leave as is)
fit_target=512               # MiB of VRAM reserved for KV-cache offload buffer
kv_k=q8_0                    # default K-cache quantization for all models
kv_v=turbo2                  # default V-cache quantization for all models

[model:my-model-32k]
name=My Model 32K            # display name (default: the model ID)
description=Optional one-liner
file=MyModel-Q4_K_M.gguf     # GGUF filename, relative to MODELS_DIR
context=32768                # context size in tokens
kv_k=q8_0                    # optional: per-model override
kv_v=turbo3                  # optional: per-model override
mtp_draft=draft.gguf         # optional: MTP speculative-decoding draft model
tools=true                   # optional: expose OpenAI tools (default: true)
```

The model ID (the section name, e.g. `my-model-32k`) is what clients use in
API requests. The **file must exist** in `MODELS_DIR` or the engine fails to
start that profile.

## Interactive wizard

`bash scripts/add-model.sh` asks for everything interactively:

- GGUF source: a local file (copied into `MODELS_DIR`) or a download URL
  (downloaded directly into `MODELS_DIR`, resumes partial downloads)
- Model ID, display name, description
- Context size in tokens
- KV cache quantizations (defaults come from `[global]`)
- Optional MTP draft model (local file or URL)

It then appends the section to `models.conf`, regenerates the config and
offers to restart the container.

## KV cache quantization options

The K and V caches can be quantized independently. K should always be more
precise than V:

| `kv_k`    | meaning                | `kv_v`    | meaning                             |
|-----------|------------------------|-----------|-------------------------------------|
| `turbo2`  | ~2-bit K cache         | `turbo2`  | ~2-bit V cache (long contexts)      |
| `turbo2`  | ~2-bit K cache         | `turbo3`  | ~3-bit V cache (slightly safer)     |
| `q8_0`    | 8-bit K cache          | `turbo2`  | ~2-bit V cache (pre-turbo2-K setup) |
| `f16`     | full precision         | `f16`     | no quantization (only for small ctx)|

Allowed values for both caches: `f16`, `bf16`, `q8_0`, `q4_0`, `q4_1`,
`iq4_nl`, `q5_0`, `q5_1`, `turbo2`, `turbo3`, `turbo4`.

**Use `turbo2` for K on GQA models** (e.g. Qwen3.8-27B: 24 heads, 4 KV
heads). The engine's auto-asymmetric logic upgrades K back to `q8_0` in that
case ("upgrading K from turbo2 to q8_0 to prevent quality degradation"),
which makes the KV cache ~4x bigger - a 13 GB model then no longer fits at
200K and gets CPU-offloaded (measured: ~3-4 tok/s instead of 23+). To keep
`turbo2` K, set `TURBO_AUTO_ASYMMETRIC=0` in `compose.yaml`.

MTP draft models expand to the full model size in VRAM when loaded (the
27B draft GGUF needs ~12.9 GB), so **MTP profiles do not fit on a 16 GB
card** together with the main model (measured: 1.9 tok/s).

## Does my model fit into VRAM?

Rule of thumb for a 16 GB GPU with the TurboQuant KV cache
(`turbo2` K + `turbo2` V):

| model size | max context (approx.) | decode speed (approx.) |
|------------|-----------------------|------------------------|
| ~4-6 GB    | 128K-250K             | 40+ tok/s              |
| ~9-10 GB   | 64K-128K              | 30+ tok/s              |
| ~13 GB     | 64K                   | ~23 tok/s (measured)   |
| ~13 GB     | 128K                  | ~15 tok/s (measured)   |
| ~13 GB     | 200K-250K             | ~11 tok/s (measured)   |

Decode speed drops as the reserved KV cache grows, even when it is almost
empty: the 27B profile measured 41.5 tok/s at 8K, 22.9 at 64K, 14.6 at 128K
and 10.9 at 200K. `-fit on` (set in every generated profile) automatically
moves KV-cache offload buffers out of VRAM when the model does not fit, so
the profile still starts - but slower. Prefer a smaller context size over a
partial offload.

## Loading a model

Nothing is loaded at startup. The first API request for a model ID starts the
engine with that model and loads it into VRAM (typically 10-30 s on an NVMe
SSD). The gateway keeps it loaded; requesting another model ID swaps it out.

```bash
curl http://127.0.0.1:9292/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"my-model-32k","messages":[{"role":"user","content":"Hello!"}]}'
```
