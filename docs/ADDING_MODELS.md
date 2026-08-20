# Adding Models

This project treats models as runtime data. Adding or tuning a model should normally require only a GGUF file plus a `llama-swap` profile. It should **not** require rebuilding the CUDA image.

## Mental model

```text
host model directory (MODELS_DIR)
        |
        | bind mount
        v
/models inside the container
        |
        | referenced by
        v
models.conf (registry, repository root)
        |
        | generate-config.sh
        v
llama-swap/config.yaml (auto-generated)
        |
        v
/v1/models
        |
        | inference request selects a model ID
        v
TurboQuant llama-server starts on demand
```

The Docker image contains the engine and gateway, not the model weights.

Every model served through the gateway is defined in **`models.conf`** at the
repository root. `llama-swap/config.yaml` is generated from it and must not be
edited by hand - regenerating overwrites it. Adding a model is three steps:

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
moe_cache=soft               # optional: MoE models, spill to RAM instead of offload
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

## 1. Locate the model directory

`compose.yaml` mounts the host directory configured as `MODELS_DIR` to `/models` inside the container.

The default is:

```text
MODELS_DIR=./models
```

A custom location can be set in the local `.env` file, for example:

```text
MODELS_DIR=D:/LLM/models
```

or on Linux:

```text
MODELS_DIR=/mnt/models
```

Do not commit machine-specific absolute paths to the repository.

## 2. Put or reuse the GGUF there

If the model file already exists in the configured host model directory, reuse it. Do not download another copy.

Example host file:

```text
D:/LLM/models/MyModel-Q4_K_M.gguf
```

Inside the container that same file is referenced as:

```text
/models/MyModel-Q4_K_M.gguf
```

Always use the container path when the model is referenced (in `models.conf`
the `file=` key is a filename relative to `MODELS_DIR`; the generator builds
the container path).

If a user supplies a model file outside the configured `MODELS_DIR`, decide explicitly whether to change the local `MODELS_DIR` arrangement or place the file in the canonical model directory. Do not silently duplicate large model files.

## 3. Add a profile to the registry

Append a `[model:<id>]` section to `models.conf` (or use the wizard), then run `bash scripts/generate-config.sh`.

The generated `llama-swap/config.yaml` profile for the example above looks like this:

```yaml
models:
  "my-model-32k":
    name: "My Model 32K"
    description: "32K profile using TurboQuant KV cache."
    cmd: |
      "${engine}" --host 127.0.0.1 --port ${PORT}
      --alias ${MODEL_ID}
      -m "/models/MyModel-Q4_K_M.gguf"
      -fit on -fitt ${fit_target}
      -c 32768
      -ctk q8_0 -ctv turbo3
      --flash-attn on --jinja -np 1
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 32768
```

### Direct path vs macro

For a single profile, prefer a direct container path:

```text
-m "/models/MyModel-Q4_K_M.gguf"
```

Use a macro/environment variable only when the same physical GGUF is deliberately reused by several profiles and the indirection makes the configuration clearer.

For example, one 27B GGUF can back several virtual profiles with different context or MTP settings. Those profiles still use one physical file.

## 4. Runtime settings belong in the registry

Per-model runtime choices belong in `models.conf` (and end up in `llama-swap/config.yaml`), including:

- context size (`context`)
- KV cache types (`kv_k`, `kv_v`)
- `--fit` and fitting target (`[global] fit_target`)
- flash attention
- parallelism
- MTP/speculative decoding (`mtp_draft`)
- MoE spill behavior (`moe_cache`)
- model aliases
- other `llama-server` flags

Changing these does not require a Docker image rebuild.

## 5. Do not rebuild the image for a model addition

For normal model installation or tuning, do **not** change:

```text
docker/Dockerfile.cuda
.github/workflows/docker-cuda.yml
```

Do not bake GGUF files into the image.

A CUDA rebuild is only appropriate when the engine/runtime image itself changes, such as a new TurboQuant revision, CUDA/runtime libraries, compiler flags, GPU architectures, or bundled gateway binary.

## 6. Validate cheaply

The gateway is configured to watch its config file. If it is already running, a regenerated config should be picked up without rebuilding the image.

First inspect the logs for config errors:

```bash
docker compose logs --tail=100 turboquant
```

Then query model discovery:

```bash
curl http://127.0.0.1:9292/v1/models
```

PowerShell:

```powershell
Invoke-RestMethod http://127.0.0.1:9292/v1/models
```

Confirm that the new virtual model ID appears.

`/v1/models` is a discovery request and should not load the model into VRAM.

Do not launch an inference request or benchmark solely as installation validation unless that test was explicitly requested.

## 7. If a config reload does not happen

A cheap container restart is different from an image rebuild:

```bash
docker compose restart turboquant
```

This reuses the existing image and normally takes seconds. It should still start with no model loaded.

Do not run `docker build`, manually dispatch the CUDA workflow, or modify the Dockerfile as a workaround for a config problem.

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

## Adding multiple runtime variants of one model

Several model IDs can point to the same GGUF while changing only runtime parameters.

Example:

```yaml
models:
  "my-model-64k":
    cmd: |
      "${engine}" --host 127.0.0.1 --port ${PORT}
      --alias ${MODEL_ID}
      -m "/models/MyModel-Q4_K_M.gguf"
      -fit on -fitt ${fit_target}
      -c 65536
      -ctk q8_0 -ctv turbo3
      --flash-attn on --jinja -np 1
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 65536

  "my-model-128k":
    cmd: |
      "${engine}" --host 127.0.0.1 --port ${PORT}
      --alias ${MODEL_ID}
      -m "/models/MyModel-Q4_K_M.gguf"
      -fit on -fitt ${fit_target}
      -c 131072
      -ctk q8_0 -ctv turbo2
      --flash-attn on --jinja -np 1
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 131072
```

No model copy and no new image are required.

## MTP / speculative decoding

If a profile uses a separate MTP draft GGUF, that draft file is also runtime data and belongs under `MODELS_DIR`.

Example command fragment:

```text
--spec-type draft-mtp
--spec-draft-model "/models/MyModel-MTP-Q4_0.gguf"
--spec-draft-n-max 3
--spec-chain 8
```

MTP draft models expand to the full model size in VRAM when loaded (the
27B draft GGUF needs ~12.9 GB), so **MTP profiles do not fit on a 16 GB
card** together with the main model (measured: 1.9 tok/s).

Do not add the draft model to the Docker image.

## Loading a model

Nothing is loaded at startup. The first API request for a model ID starts the
engine with that model and loads it into VRAM (typically 10-30 s on an NVMe
SSD). The gateway keeps it loaded; requesting another model ID swaps it out.

```bash
curl http://127.0.0.1:9292/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"my-model-32k","messages":[{"role":"user","content":"Hello!"}]}'
```

## Checklist for agents

When asked to install a model, determine:

1. Is the GGUF already available locally?
2. What host directory is currently used as `MODELS_DIR`?
3. What exact filename will appear under `/models`?
4. What virtual model ID should be exposed?
5. What context/KV/MTP/runtime settings are desired?
6. Can the change be done entirely in `models.conf`? For a normal model addition, the answer should be yes.
7. Does `/v1/models` show the new ID after the edit?

If an action would trigger a download, CUDA build, CI job, benchmark, or other expensive work, explain that consequence and obtain explicit approval first unless the user already requested that exact action.