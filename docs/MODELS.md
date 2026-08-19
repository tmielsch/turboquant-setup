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

| `kv_k` | meaning          | `kv_v` | meaning                               |
|--------|------------------|--------|---------------------------------------|
| `q8_0` | 8-bit K cache    | `turbo2` | ~2-bit V cache (long contexts)     |
| `q8_0` | 8-bit K cache    | `turbo3` | ~3-bit V cache (slightly safer)    |
| `q8_0` | 8-bit K cache    | `turbo4` | ~4-bit V cache (most conservative) |
| `f16`  | full precision   | `f16`   | no quantization (only for small ctx)  |

Lower bit V caches free more VRAM for context length, at the cost of some
fidelity. `turbo2` is the long-context lever: with it, a 13 GB model reaches
200K-250K context on a 16 GB GPU.

## Does my model fit into VRAM?

Rule of thumb for a 16 GB GPU with the TurboQuant KV cache
(`q8_0` K + `turbo2` V):

| model size | max context (approx.) |
|------------|-----------------------|
| ~4-6 GB    | 128K-250K             |
| ~9-10 GB   | 64K-128K              |
| ~13 GB     | 200K-250K             |
| ~18 GB+    | does not fit          |

`-fit on` (set in every generated profile) automatically moves KV-cache
offload buffers out of VRAM when the model does not fit, so the profile still
starts - but slower. Prefer a smaller quantization of your model over a
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
