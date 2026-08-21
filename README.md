# TurboQuant Model Server

A small Docker setup for serving multiple local GGUF runtime profiles through one OpenAI-compatible endpoint.

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

## Repository state vs local state

There are deliberately two different kinds of state, with no generator between them:

- **`llama-swap/config.example.yaml`** — tracked repository baseline / starter config.
- **`llama-swap/config.yaml`** — real machine-local runtime config. It is gitignored and is the only config llama-swap actually runs.

On a new machine, copy the example once. After that, edit the local `config.yaml` directly. Setup, Git pulls, agents, and maintenance scripts must never overwrite it.

There is no `models.conf`, config generator, model registry, or synchronization layer.

Configuration boundaries:

- `llama-swap/config.yaml` — local model IDs, GGUF paths under `/models`, context, KV cache, MTP, MoE, fitting/offload and all per-model `llama-server` arguments.
- `llama-swap/config.example.yaml` — optional tracked baseline for bootstrapping a new machine; not the live config.
- `.env` — machine-local `MODELS_DIR`.
- `compose.yaml` — stable container/GPU/mount/port settings.
- `docker/Dockerfile.cuda` — runtime image; change only when the engine itself changes.

## Quick start on a new machine

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
cp .env.example .env
cp llama-swap/config.example.yaml llama-swap/config.yaml
```

Set the model directory in `.env`:

```dotenv
MODELS_DIR=/path/to/models
```

Then:

```bash
docker compose pull
docker compose up -d
```

The copy step is **bootstrap only**. If `llama-swap/config.yaml` already exists, do not replace it with the example.

No model is loaded at startup. Check discovery with:

```bash
curl http://127.0.0.1:9292/v1/models
```

Endpoints:

| Endpoint | Purpose |
|---|---|
| `http://127.0.0.1:9292/v1` | OpenAI-compatible API |
| `http://127.0.0.1:9292/v1/models` | Model discovery |
| `http://127.0.0.1:9292/ui` | llama-swap UI |

## Existing installations: migrate without losing local config

Before switching an older checkout to this architecture, preserve the **current live YAML**, not the old registry:

```bash
cp llama-swap/config.yaml llama-swap/config.yaml.backup
```

After updating the repository, restore that file as the local runtime config if needed:

```bash
cp llama-swap/config.yaml.backup llama-swap/config.yaml
```

Do not run an old config generator during migration. Once migrated, `config.yaml` is local and ignored by Git.

## Add or tune a model

Edit your local `llama-swap/config.yaml` directly. A profile is simply a llama-swap model entry whose `cmd` starts `llama-server` with the desired flags.

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

The same GGUF can have another virtual profile with different flags. That is the abstraction llama-swap already provides; no extra registry is needed.

Because the container starts llama-swap with config watching enabled, valid local edits may be picked up automatically. If a reload is needed:

```bash
docker compose restart turboquant
```

A model/profile change never requires rebuilding the CUDA image.

More examples: [docs/ADDING_MODELS.md](docs/ADDING_MODELS.md).

## OpenCode

Use an OpenAI-compatible provider with base URL:

```text
http://127.0.0.1:9292/v1
```

The local model IDs are exposed through `/v1/models` and can be addressed independently by OpenCode.

## Repository maintenance

Normal changes fall into four categories:

1. **Local model/profile change** → edit local `llama-swap/config.yaml`; normally do not commit it.
2. **Change the starter baseline for future machines** → intentionally edit `llama-swap/config.example.yaml`.
3. **Machine path change** → edit local `.env`.
4. **Engine/runtime change** → update `docker/Dockerfile.cuda` and rebuild/publish the image intentionally.

Automated coding agents must read [AGENTS.md](AGENTS.md) before making changes.

## Engine

Inference engine: [TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant), currently built from `feature/turboquant-kv-cache`.

## License

MIT
