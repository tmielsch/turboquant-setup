# Agent Instructions

These rules apply to every automated coding agent working in this repository.

## The architecture in one sentence

`llama-swap/config.yaml` is the **single source of truth** for every model ID and every per-model `llama-server` runtime profile.

Do not create another model registry, generated config, profile database, INI layer, template layer, or synchronization script on top of it.

## Configuration boundaries

### `llama-swap/config.yaml`

Use this file directly for:

- virtual model IDs and display names
- GGUF paths under `/models`
- context size (`-c`)
- KV cache types (`-ctk`, `-ctv`)
- TurboQuant options
- `--fit` / offload behavior
- Flash Attention and parallelism
- MTP/speculative decoding
- MoE cache / CPU MoE settings
- sampling/runtime flags
- any other per-model `llama-server` arguments

Several virtual model IDs may intentionally reference the same physical GGUF with different arguments. This is the normal design.

When adding or tuning a model, modify only the relevant block(s). Preserve unrelated profiles exactly.

### `.env`

Use only for machine-local settings such as `MODELS_DIR`.

Do not commit host-specific absolute model paths. Model commands inside llama-swap always reference the container mount, e.g. `/models/MyModel.gguf`.

### `compose.yaml`

Use only for stable container-level concerns such as:

- image
- ports
- mounts
- GPU access
- container-wide environment variables

Do not move model-specific runtime settings into Compose.

### `docker/Dockerfile.cuda`

Change only when the runtime image itself must change, for example:

- a different TurboQuant/llama.cpp revision
- CUDA/runtime dependency changes
- compiler/build flags or GPU architecture
- a different bundled llama-swap version

Adding or tuning a model does not require an image rebuild.

## Critical preservation rule

Never regenerate, replace, reconstruct, or overwrite the whole `llama-swap/config.yaml` from another file.

Before changing it:

1. Read the current file.
2. Treat every existing entry as user-maintained state.
3. Make the smallest intentional edit needed.
4. Do not normalize, reorder, rewrite, or delete unrelated entries.

There is no `models.conf` workflow and there must not be one again.

## New machines

Machine bootstrap and configuration maintenance are separate concerns.

Normal bootstrap is:

```text
git clone
  -> create local .env / set MODELS_DIR
  -> docker compose pull
  -> docker compose up -d
```

Bootstrap must not generate or rewrite the tracked llama-swap configuration.

## Adding a model

Read `docs/ADDING_MODELS.md`.

The normal flow is:

```text
existing GGUF in MODELS_DIR
  -> add one or more entries directly to llama-swap/config.yaml
  -> llama-swap config reload (or cheap container restart if necessary)
  -> verify /v1/models
```

Do not copy or redownload a large GGUF if the user already has it.

Do not invent a helper abstraction merely because several profiles share a file. Repeating a short `cmd` block is preferable to introducing another mutable configuration layer.

## Expensive side effects

Treat user time, compute, bandwidth, and money as scarce resources.

Unless explicitly requested, do not:

- rebuild the CUDA image
- trigger or re-run CI
- download GGUFs
- install packages
- start large-model inference
- run benchmarks
- restart workloads unnecessarily

Prefer static/config validation first.

## Cheap validation

For a normal config edit:

1. Inspect YAML structure and indentation.
2. If the gateway is already running, inspect logs for config reload errors.
3. Check model discovery:

```bash
curl http://127.0.0.1:9292/v1/models
```

This should not load a model into VRAM.

Useful commands:

```bash
docker compose ps
docker compose logs --tail=100 turboquant
curl http://127.0.0.1:9292/v1/models
```

Do not send an inference request just to prove model discovery works.

## Preserve zero VRAM at idle

The persistent service is llama-swap, not an always-loaded LLM. A child `llama-server` should start only when a configured model ID is requested.

## If documentation and implementation disagree

Do not pick one arbitrarily and proceed destructively. Treat the existing `llama-swap/config.yaml` and current Compose/Docker runtime behavior as authoritative, point out the inconsistency, and fix documentation without discarding user state.
