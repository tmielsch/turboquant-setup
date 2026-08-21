# Agent Instructions

These rules apply to every automated coding agent working in this repository.

## Architecture in one sentence

The live model/runtime configuration is the machine-local, gitignored `llama-swap/config.yaml`. The repository only tracks `llama-swap/config.example.yaml` as a bootstrap baseline.

Do not create another model registry, generated config, profile database, INI layer, merge layer, synchronization script, or automatic import/export workflow on top of llama-swap.

## Local state vs repository state

### `llama-swap/config.yaml` — live local state

This is the configuration llama-swap actually runs. It may contain machine-specific model selections and locally evolved profiles that are intentionally not committed.

Use it for:

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

Several virtual model IDs may intentionally reference the same physical GGUF with different arguments.

**Never assume local config changes should be committed back to the repository.** Only change repository state when the user explicitly asks for repository changes.

When working on a machine-local config, read the existing local file first and modify only the requested block(s). Preserve unrelated profiles exactly.

### `llama-swap/config.example.yaml` — tracked baseline

This is only the default starter state for a new machine. It is not automatically synchronized with `config.yaml`.

Do not overwrite an existing local `config.yaml` from this file. Do not treat differences between the two files as drift that must be reconciled.

Change the example only when the user explicitly wants the repository's future bootstrap baseline changed.

### `.env`

Machine-local settings such as `MODELS_DIR`. Do not commit host-specific absolute paths.

### `compose.yaml`

Stable container-level concerns only: image, ports, mounts, GPU access, container-wide environment variables.

### `docker/Dockerfile.cuda`

Change only when the runtime image itself must change, for example a different TurboQuant/llama.cpp revision, CUDA/runtime dependency, build flags, GPU architecture, or llama-swap version.

Adding or tuning a model does not require an image rebuild.

## Critical preservation rules

1. Never regenerate, replace, reconstruct, normalize, or overwrite the whole local `llama-swap/config.yaml` from another file.
2. Never copy `config.example.yaml` over an existing `config.yaml`.
3. Never infer that local runtime changes belong in Git.
4. Never add a second schema merely to make repeated YAML shorter.
5. Do not reintroduce `models.conf`, `generate-config.sh`, or a parallel profile registry.

If the user asks to modify local runtime configuration but the local file is not available to the agent, ask for/read that file rather than editing the repository baseline as a substitute.

## New machines

Bootstrap and maintenance are separate concerns.

Initial bootstrap:

```text
git clone
  -> copy .env.example to .env if .env does not exist
  -> copy llama-swap/config.example.yaml to llama-swap/config.yaml if config.yaml does not exist
  -> set MODELS_DIR
  -> docker compose pull
  -> docker compose up -d
```

The copy operations are one-time initialization only and must refuse to overwrite existing local files.

After bootstrap, normal model maintenance touches only the local `config.yaml`.

## Adding a model

Read `docs/ADDING_MODELS.md`.

Normal flow:

```text
existing GGUF in MODELS_DIR
  -> add one or more entries directly to local llama-swap/config.yaml
  -> llama-swap config reload (or cheap restart if necessary)
  -> verify /v1/models
```

Do not copy or redownload a large GGUF if the user already has it.

## Expensive side effects

Unless explicitly requested, do not rebuild the CUDA image, trigger CI, download GGUFs, install packages, run large-model inference, run benchmarks, or restart workloads unnecessarily.

Prefer static/config validation first.

## Cheap validation

For a normal local config edit:

1. Inspect YAML structure and indentation.
2. If the gateway is running, inspect logs for reload errors.
3. Check discovery:

```bash
curl http://127.0.0.1:9292/v1/models
```

This should not load a model into VRAM.

## Preserve zero VRAM at idle

The persistent service is llama-swap, not an always-loaded LLM. A child `llama-server` should start only when a configured model ID is requested.

## If documentation and implementation disagree

Do not proceed destructively. Preserve local runtime state first, identify which file is live, and fix documentation or repository baseline without discarding machine-local configuration.
