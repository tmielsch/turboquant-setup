# TurboQuant Setup

Prebuilt TurboQuant + `llama-swap` setup for running long-context Qwen models on a 16 GB NVIDIA GPU, primarily tested for an RTX 4070 Ti SUPER.

## Goals

- Qwen3.8-27B `UD-Q3_K_XL`
- 200K context as the main profile, 250K as the maximum profile
- TurboQuant KV cache with `q8_0` K + `turbo2` V
- TheTom `llama-cpp-turboquant` as the inference engine
- `llama-swap` as a persistent OpenAI-compatible gateway
- no model loaded at startup; a model is launched only when requested
- the same model IDs and API endpoint on Windows and Linux
- easy use from Hermes, OpenCode, or any OpenAI-compatible client

## Prebuilt Docker image

The normal installation path does **not** compile CUDA or llama.cpp locally.

Image:

```text
ghcr.io/tmielsch/turboquant-setup:cuda
```

If the GHCR package is public, no registry login is required.

### Pull the image only

This works from any directory:

```bash
docker pull ghcr.io/tmielsch/turboquant-setup:cuda
```

### Recommended: run with Docker Compose

`docker compose` must be run from the cloned repository directory because `compose.yaml` and `llama-swap/config.yaml` are stored there.

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
cp .env.example .env
```

Edit `.env` if your GGUF files are not in `./models`:

```text
MODELS_DIR=/path/to/your/models
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

Endpoints:

- OpenAI API: `http://127.0.0.1:9292/v1`
- Model discovery: `http://127.0.0.1:9292/v1/models`
- llama-swap UI: `http://127.0.0.1:9292/ui`

The container starts only `llama-swap`. No LLM is loaded until a client requests one of the configured model IDs.

## Requirements

### Windows

- NVIDIA driver
- Docker Desktop using the WSL2 backend
- working NVIDIA GPU passthrough to Docker

### Linux

- NVIDIA driver
- Docker
- NVIDIA Container Toolkit / working NVIDIA Docker runtime

The CUDA/CMake build happens in GitHub Actions, not on the target machine.

## Model files

Models are **not included in the Docker image**. They are bind-mounted read-only from `MODELS_DIR` into `/models`.

Expected filenames:

```text
Qwen3.5-9B-Q4_K_M.gguf
Qwen3.8-27B-UD-Q3_K_XL.gguf
mtp-Qwen3.8-27B-Q4_0.gguf
```

The MTP draft model is only needed for the `-mtp` profiles.

All Qwen3.8-27B profiles use the same main GGUF file. The 200K/250K/MTP variants are runtime configurations, not separate model copies and not separate Docker images.

## Adding or installing models

Adding a GGUF is a runtime configuration task, not an image build.

The normal flow is:

```text
GGUF in host MODELS_DIR
    -> mounted as /models/<filename>.gguf
    -> add a profile in llama-swap/config.yaml
    -> verify the model ID through /v1/models
```

Do **not** rebuild the CUDA image merely to add a model or change context/KV/MTP parameters.

See [`docs/ADDING_MODELS.md`](docs/ADDING_MODELS.md) for the complete model installation workflow.

Automated coding agents should read [`AGENTS.md`](AGENTS.md) before modifying this repository. It defines the architecture boundaries and the rules for avoiding unnecessary builds, downloads, CI runs, and other expensive side effects.

## Available model IDs

| Model ID | Context | KV cache | MTP |
|---|---:|---|---|
| `qwen3.5-9b-32k` | 32K | `q8_0` K / `turbo3` V | No |
| `qwen3.8-27b-200k` | 200K | `q8_0` K / `turbo2` V | No |
| `qwen3.8-27b-250k` | 250K | `q8_0` K / `turbo2` V | No |
| `qwen3.8-27b-200k-mtp` | 200K | `q8_0` K / `turbo2` V | Yes |
| `qwen3.8-27b-250k-mtp` | 250K | `q8_0` K / `turbo2` V | Yes |

## Architecture

```text
Hermes / OpenCode / OpenAI-compatible client
                 |
                 |  http://127.0.0.1:9292/v1
                 v
            llama-swap
                 |
                 |  requested model ID
                 v
      TurboQuant llama-server (on demand)
                 |
                 +-- host-mounted GGUF
                 +-- context / KV / MTP runtime profile
```

`llama-swap` exposes the virtual model IDs through `/v1/models`. Switching model IDs starts the matching `llama-server` command and stops the previous one when required.

## Hermes

Use the gateway as a custom OpenAI-compatible provider:

```yaml
custom_providers:
  - name: turboquant
    base_url: http://127.0.0.1:9292/v1
    models:
      qwen3.5-9b-32k:
        context_length: 32768
      qwen3.8-27b-200k:
        context_length: 200000
      qwen3.8-27b-250k:
        context_length: 250000
      qwen3.8-27b-200k-mtp:
        context_length: 200000
      qwen3.8-27b-250k-mtp:
        context_length: 250000
```

Example model switches:

```text
/model custom:turboquant:qwen3.8-27b-200k
/model custom:turboquant:qwen3.8-27b-250k
/model custom:turboquant:qwen3.8-27b-200k-mtp
```

See `docs/HERMES.md` for additional details.

## OpenCode

Use the same OpenAI-compatible endpoint:

```text
http://127.0.0.1:9292/v1
```

Model discovery is available through `/v1/models`.

## Troubleshooting

### `docker compose pull` says `no configuration file provided`

You are not in the repository directory. Run:

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
docker compose pull
```

### `docker pull` returns a Docker Desktop `500 Internal Server Error`

If the error references a local Docker Desktop pipe such as `dockerDesktopLinuxEngine`, first verify that the Docker engine itself is healthy:

```bash
docker version
docker info
```

If the server section fails, fix/restart Docker Desktop before troubleshooting GHCR or this image. No project rebuild is required for that problem.

### Check container state and logs

```bash
docker compose ps
docker compose logs -f
```

## Native installation

Native Windows/Linux build scripts remain in the repository for development and debugging, but the prebuilt Docker image is the recommended path for normal use.

## Container build

`docker/Dockerfile.cuda` builds a single CUDA/TurboQuant `llama-server` runtime plus `llama-swap`.

GitHub Actions publishes:

```text
ghcr.io/tmielsch/turboquant-setup:cuda
```

The expensive CUDA build runs on `main` or via manual workflow dispatch. Runtime model/profile changes do not require rebuilding the image.

## Engine

Inference engine: `TheTom/llama-cpp-turboquant`, branch `feature/turboquant-kv-cache`.
