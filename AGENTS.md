# Agent Instructions

These instructions apply to automated coding agents working in this repository.

## Architecture

- The Docker image contains the CUDA runtime, TurboQuant `llama-server`, and `llama-swap`.
- GGUF model files are runtime data. They live outside the image and are mounted read-only at `/models` through `MODELS_DIR`.
- `llama-swap/config.yaml` is the source of truth for virtual model IDs and llama-server runtime profiles.
- `compose.yaml` defines stable container-level concerns such as the image, mounts, ports, and environment.
- Adding, removing, or tuning a model normally must **not** rebuild the Docker image.

## Expensive side effects

Treat user time, compute, bandwidth, and money as scarce resources. Before any action that may trigger a build, CI job, test suite, deploy, download, install, cloud/API/GPU workload, or other slow/costly side effect, identify the consequence and get explicit user approval unless that exact action was already requested.

Batch changes and do cheap/static validation first. Never trigger redundant or parallel expensive runs. Once a long-running job starts, freeze anything that would invalidate or restart it unless a critical issue is found and the user explicitly chooses to restart. Never trade the user's waiting time for minor cleanup or optimization without asking. If duration/cost is unknown or a side effect is uncertain, assume it may be expensive and ask first.

In particular:

- Do **not** modify `docker/Dockerfile.cuda` or `.github/workflows/docker-cuda.yml` merely to add or tune a model.
- Do **not** trigger or re-run the CUDA image workflow unless the user explicitly asks for it or an engine/image change genuinely requires it and the user approves.
- Do **not** download a model if the user has already supplied a usable local file.
- Do **not** start benchmarks or large model inference as validation unless the user explicitly asks for it.

## Adding models

Read [`docs/ADDING_MODELS.md`](docs/ADDING_MODELS.md) before adding a model.

For a normal GGUF model addition:

1. Determine the host directory configured as `MODELS_DIR`.
2. Reuse the user's existing GGUF if it is already present there. If the supplied file is elsewhere, do not silently copy, move, or redownload it; either use/update the local `MODELS_DIR` arrangement or ask the user which location should be canonical.
3. Add a virtual model entry to `llama-swap/config.yaml`.
4. Inside llama-swap commands, reference model files by their **container path**, e.g. `/models/MyModel.gguf`, never by a host-specific Windows or Linux path.
5. Put runtime choices such as context length, KV cache type, GPU fitting/offload behavior, MTP/speculative decoding, aliases, and other `llama-server` flags in `llama-swap/config.yaml`.
6. Prefer a direct `/models/<filename>.gguf` path for one-off models. Add a Compose environment variable/macro only when the same physical model is intentionally shared by several profiles and the indirection improves maintainability.
7. Do not edit the Dockerfile, CI workflow, or bake the GGUF into the image.
8. Validate that the new model ID appears in `/v1/models`. This discovery request must not load the model.

## Model installation means configuration, not image building

When a user says something like:

> Install this model; the GGUF is already here.

Interpret the normal workflow as:

```text
existing GGUF
    -> host MODELS_DIR
    -> mounted as /models/<file>.gguf
    -> llama-swap/config.yaml profile
    -> visible through /v1/models
```

It does **not** imply:

```text
Dockerfile change -> CUDA rebuild -> new image
```

## Runtime configuration boundaries

Use `llama-swap/config.yaml` for:

- model IDs and aliases
- GGUF paths under `/models`
- context size (`-c`)
- KV cache types (`-ctk`, `-ctv`)
- `--fit` / fitting target
- flash attention and parallelism flags
- MTP/speculative decoding configuration
- any other per-model `llama-server` arguments

Use `.env` / `MODELS_DIR` for host-specific model directory selection. Do not commit machine-specific absolute paths.

Use `compose.yaml` only when a container-level setting truly changes. Recreating/restarting a container is not the same as rebuilding the image, but still avoid unnecessary changes.

Use `docker/Dockerfile.cuda` only when the runtime image itself must change, for example:

- a different TurboQuant/llama.cpp engine revision
- CUDA/runtime library changes
- compiler/build flags or GPU architecture changes
- a different bundled `llama-swap` binary

Such changes can trigger an expensive CUDA build and require explicit awareness/approval.

## Validation

Prefer the cheapest validation that proves the change:

1. Inspect the edited YAML for schema/indentation consistency with existing entries.
2. If the gateway is already running, check its logs for config reload errors.
3. Query `http://127.0.0.1:9292/v1/models` and confirm the new model ID is listed.
4. Do not send an inference request merely to prove discovery works.
5. Only load/benchmark the model when the user asks to test inference or performance.

Useful commands from the repository directory:

```bash
docker compose ps
docker compose logs --tail=100 turboquant
curl http://127.0.0.1:9292/v1/models
```

On PowerShell, model discovery can be checked with:

```powershell
Invoke-RestMethod http://127.0.0.1:9292/v1/models
```

## Preserve the zero-VRAM-at-idle design

The gateway should start without loading an LLM. Model discovery and configuration changes must not eagerly load model weights. A `llama-server` child should be launched only when an inference request selects a configured model ID.
