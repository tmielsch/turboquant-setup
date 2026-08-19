# TurboQuant Setup

Run long-context Qwen models with a TurboQuant KV cache on a **16 GB NVIDIA
GPU** (tested with an RTX 4070 Ti SUPER), served through a single
OpenAI-compatible API endpoint.

- Qwen3.8-27B with **200K context** (250K as maximum profile)
- TurboQuant KV cache (`turbo2` K + `turbo2` V) - up to ~10x less KV memory
- Measured 23 tok/s at 64K context on a 16 GB GPU (see model table below)
- `llama-swap` as a persistent gateway: **no model loaded at startup**, models
  are loaded on demand and hot-swapped when you switch model IDs
- Same model IDs and API endpoint on Windows and Linux
- **Adding models does not require a Docker image rebuild** - edit
  `models.conf` (or run `scripts/add-model.sh`) and restart the container

Works with Hermes, OpenCode, or any OpenAI-compatible client.

## Architecture

```
Hermes / OpenCode / any OpenAI-compatible client
                 |
                 |  http://127.0.0.1:9292/v1
                 v
            llama-swap (gateway)
                 |
                 |  requested model ID
                 v
      TurboQuant llama-server (started on demand)
                 |
                 +-- host-mounted GGUF files
                 +-- context / KV / MTP runtime profile
```

The gateway exposes virtual model IDs through `/v1/models`. Requesting a model
ID starts the matching `llama-server` process with the configured profile;
requesting a different ID swaps them.

## Requirements

- NVIDIA GPU with at least 16 GB VRAM (other sizes work, adjust models
  accordingly - see [docs/MODELS.md](docs/MODELS.md))
- NVIDIA driver (CUDA-capable)
- Docker with working NVIDIA GPU passthrough:
  - **Linux:** Docker + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
    (then `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`)
  - **Windows:** Docker Desktop with WSL2 backend + NVIDIA GPU passthrough
- ~21 GB disk space for the reference models (plus the image)

No local CUDA/CMake toolchain is needed - the engine image is prebuilt.

## Quick start

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
cp .env.example .env
```

If your GGUF files are not in `./models`, point `MODELS_DIR` at them:

```bash
# .env
MODELS_DIR=/path/to/your/models
```

Download the reference models (optional but recommended, ~21 GB total):

```bash
mkdir -p models
curl -L -o models/Qwen3.5-9B-Q4_K_M.gguf \
  https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf
curl -L -o models/Qwen3.8-27B-UD-Q3_K_XL.gguf \
  https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q3_K_XL.gguf
curl -L -o models/mtp-Qwen3.8-27B-Q4_0.gguf \
  https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/MTP/mtp-Qwen3.8-27B-Q4_0.gguf
```

Then:

```bash
docker compose pull
docker compose up -d
```

Check the gateway:

```bash
curl http://127.0.0.1:9292/v1/models
```

The container starts only `llama-swap` (with `restart: unless-stopped`, so it
comes back up after reboots). No LLM is loaded until a client requests one of
the configured model IDs.

### Endpoints

| Endpoint | Purpose |
|---|---|
| `http://127.0.0.1:9292/v1` | OpenAI-compatible API |
| `http://127.0.0.1:9292/v1/models` | Model discovery |
| `http://127.0.0.1:9292/ui` | llama-swap web UI |

## Adding models (no image rebuild!)

Each model is a section in [`models.conf`](models.conf). The Docker image
contains only the engine binaries; models and runtime profiles are mounted in
as files, so changing them is a config edit + container restart (seconds).

**Easiest way - interactive wizard:**

```bash
bash scripts/add-model.sh
```

It asks for the GGUF file (local path or download URL), model ID, context
size, KV cache options and an optional MTP draft, then updates the config and
offers to restart the container. Note: MTP profiles only make sense on GPUs
with 24+ GB VRAM (see the model table below).

**Or by hand:** append a section to `models.conf`, then regenerate:

```bash
# models.conf
[model:my-model-64k]
name=My Model 64K
file=MyModel-Q4_K_M.gguf
context=65536

bash scripts/generate-config.sh
docker compose restart turboquant
```

Full reference (options, KV cache choices, VRAM fit guide):
[docs/MODELS.md](docs/MODELS.md).

## Default model IDs

| Model ID | Context | KV cache | Decode (16 GB GPU) |
|---|---|---|---|
| `qwen3.5-9b-32k` | 32K | `q8_0` K / `turbo3` V | ~40+ tok/s |
| `qwen3.8-27b-64k` | 64K | `turbo2` K / `turbo2` V | ~23 tok/s |
| `qwen3.8-27b-128k` | 128K | `turbo2` K / `turbo2` V | ~15 tok/s |
| `qwen3.8-27b-200k` | 200K | `turbo2` K / `turbo2` V | ~11 tok/s |
| `qwen3.8-27b-250k` | 250K | `turbo2` K / `turbo2` V | ~10 tok/s |

All 27B variants use the same main GGUF file - they are runtime profiles, not
separate model copies. Decode speed drops as the reserved KV cache grows, so
use the smallest context that covers your workload. MTP profiles are not
viable on a 16 GB card (the draft expands to ~12.9 GB in VRAM).

## Usage

```bash
curl http://127.0.0.1:9292/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-27b-64k","messages":[{"role":"user","content":"Hello!"}]}'
```

The first request loads the model into VRAM (10-30 s on NVMe), subsequent
requests run at full speed.

### Hermes

Use the gateway as a custom OpenAI-compatible provider:

```yaml
custom_providers:
  - name: turboquant
    base_url: http://127.0.0.1:9292/v1
    models:
      qwen3.5-9b-32k:
        context_length: 32768
      qwen3.8-27b-64k:
        context_length: 65536
      qwen3.8-27b-128k:
        context_length: 131072
      qwen3.8-27b-200k:
        context_length: 200000
      qwen3.8-27b-250k:
        context_length: 250000
```

Model switches: `/model custom:turboquant:qwen3.8-27b-64k`

### OpenCode

Add the endpoint as an OpenAI-compatible provider with base URL
`http://127.0.0.1:9292/v1`; model discovery runs through `/v1/models`.

## Troubleshooting

### `docker compose pull` says "no configuration file provided"

Run compose from the repository directory (where `compose.yaml` lives).

### Container fails to start: `could not select device driver "nvidia"`

The NVIDIA container runtime is missing or not registered with Docker.
Linux:

```bash
sudo pacman -S nvidia-container-toolkit      # Arch / CachyOS
# or: sudo apt install nvidia-container-toolkit   (Debian/Ubuntu)
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### `permission denied while trying to connect to the docker API`

Your user is not in the `docker` group (or the group was added after login):

```bash
sudo usermod -aG docker "$USER"
# then log out and back in (or run: newgrp docker)
```

### Engine starts but generation is very slow

The model + KV cache does not fit in VRAM and parts are offloaded to system
RAM. Either use a smaller quantization of the model, reduce the context size,
or use a more aggressive V-cache quantization (see
[docs/MODELS.md](docs/MODELS.md)).

### Check container state and logs

```bash
docker compose ps
docker compose logs -f
```

## Native installation (without Docker)

The prebuilt Docker image is the recommended path. Native build scripts for
Windows/Linux remain in `scripts/` for development and debugging - see
[docs/SETUP.md](docs/SETUP.md). Note that the native path compiles the
TurboQuant engine from source (CUDA/CMake, takes a long time).

## Building the container image

`docker/Dockerfile.cuda` builds the TurboQuant `llama-server` runtime plus
`llama-swap` in one image. GitHub Actions publishes
`ghcr.io/tmielsch/turboquant-setup:cuda` on `main` or via manual workflow
dispatch. Model/profile changes never require rebuilding the image.

## Engine

Inference engine: [TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant),
branch `feature/turboquant-kv-cache`.

## License

MIT
