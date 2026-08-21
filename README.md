# TurboQuant Model Server

A small Docker setup for serving multiple local GGUF runtime profiles through one OpenAI-compatible endpoint.

The intended workflow is simple:

```text
OpenCode / Hermes / OpenAI-compatible client
                  |
                  | http://127.0.0.1:9292/v1
                  v
             llama-swap
                  |
                  | selected virtual model ID
                  v
        TurboQuant llama-server
                  |
                  v
        host-mounted GGUF files
```

`llama-swap` stays running while LLMs are loaded only on demand. Multiple model IDs may point at the same physical GGUF with different context sizes, KV cache formats, MTP settings, or other `llama-server` flags.

## One configuration file

**`llama-swap/config.yaml` is the only source of truth for models and runtime profiles.**

There is deliberately no model registry, config generator, or second abstraction layer. To add or tune a model, edit `llama-swap/config.yaml` directly.

Configuration boundaries:

- `llama-swap/config.yaml` — model IDs, GGUF paths, context, KV cache, MTP, MoE, fitting/offload and all other per-model `llama-server` arguments.
- `.env` — machine-local `MODELS_DIR` only.
- `compose.yaml` — stable container/GPU/mount/port settings.
- `docker/Dockerfile.cuda` — the TurboQuant/llama.cpp and llama-swap runtime image. Change this only when the engine itself must change.

## Quick start on a new machine

Requirements:

- Docker
- NVIDIA GPU support in Docker
- the GGUF files you want to serve

Clone the repository and create the local environment file:

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
cp .env.example .env
```

Point `MODELS_DIR` at the directory containing your GGUF files:

```dotenv
MODELS_DIR=/path/to/models
```

Then start the server:

```bash
docker compose pull
docker compose up -d
```

No model is loaded at startup. Check model discovery with:

```bash
curl http://127.0.0.1:9292/v1/models
```

Endpoints:

| Endpoint | Purpose |
|---|---|
| `http://127.0.0.1:9292/v1` | OpenAI-compatible API |
| `http://127.0.0.1:9292/v1/models` | Model discovery |
| `http://127.0.0.1:9292/ui` | llama-swap UI |

See [docs/SETUP.md](docs/SETUP.md) for host prerequisites.

## Add or tune a model

Edit `llama-swap/config.yaml` directly. A profile is just a llama-swap model entry whose command starts `llama-server` with the desired arguments.

Example:

```yaml
models:
  "ridge-64k-quality":
    name: "Qwen3.8 27B Ridge - 64K Quality"
    cmd: |
      "${engine}" --host 127.0.0.1 --port ${PORT}
      --alias ${MODEL_ID}
      -m "/models/Qwen3.8-27B-Ridge.gguf"
      -fit on -fitt ${fit_target}
      -c 65536
      -ctk q8_0 -ctv turbo3
      --flash-attn on --jinja -np 1
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 65536
```

The same GGUF can back another profile:

```yaml
  "ridge-250k-fast":
    name: "Qwen3.8 27B Ridge - 250K Fast"
    cmd: |
      "${engine}" --host 127.0.0.1 --port ${PORT}
      --alias ${MODEL_ID}
      -m "/models/Qwen3.8-27B-Ridge.gguf"
      -fit on -fitt ${fit_target}
      -c 250000
      -ctk turbo2 -ctv turbo2
      --flash-attn on --jinja -np 1
    capabilities:
      in: [text]
      out: [text]
      tools: true
      context: 250000
```

Because the container starts llama-swap with config watching enabled, edits can be picked up without rebuilding the image. If a reload is needed:

```bash
docker compose restart turboquant
```

A model/profile change must **never** require regenerating the whole config or rebuilding the CUDA image.

More examples and rules: [docs/ADDING_MODELS.md](docs/ADDING_MODELS.md).

## OpenCode

Configure an OpenAI-compatible provider with:

```text
http://127.0.0.1:9292/v1
```

The model IDs exposed by `llama-swap/config.yaml` are available through `/v1/models`, so OpenCode can address the different runtime profiles independently.

## Repository maintenance

Normal changes fall into three categories:

1. **Model/profile change** → edit `llama-swap/config.yaml` only.
2. **Machine path change** → edit local `.env` only.
3. **Engine/runtime change** → update `docker/Dockerfile.cuda` and rebuild/publish the image intentionally.

There is no generated model configuration and no parallel native profile registry.

Automated coding agents must read [AGENTS.md](AGENTS.md) before making changes.

## Engine

Inference engine: [TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant), currently built from `feature/turboquant-kv-cache`.

## License

MIT
