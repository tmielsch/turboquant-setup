# Setup

This repository is designed to be moved to a new machine without regenerating model configuration.

## Architecture

There are only two runtime layers:

1. **llama-swap** — persistent OpenAI-compatible gateway on port `9292`.
2. **TurboQuant llama-server** — child process started on demand for the selected virtual model ID.

`llama-swap/config.yaml` is tracked in Git and is the canonical model/runtime configuration. Machine setup must not rewrite it.

## Requirements

- Docker
- NVIDIA GPU with working container passthrough
- GGUF files stored somewhere on the host

Linux additionally needs the NVIDIA Container Toolkit configured for Docker. Windows uses Docker Desktop/WSL2 GPU passthrough.

## Bootstrap a new machine

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
cp .env.example .env
```

Set the host model directory in `.env`:

```dotenv
MODELS_DIR=/path/to/your/gguf/files
```

Examples:

```dotenv
# Linux
MODELS_DIR=/mnt/models

# Windows / Docker Desktop
MODELS_DIR=C:/LLM/models
```

Then:

```bash
docker compose pull
docker compose up -d
```

The container has `restart: unless-stopped`, so it returns after reboot. No LLM is loaded until a configured model ID is requested.

## Verify

```bash
docker compose ps
curl http://127.0.0.1:9292/v1/models
```

Useful endpoints:

- API: `http://127.0.0.1:9292/v1`
- model discovery: `http://127.0.0.1:9292/v1/models`
- llama-swap UI: `http://127.0.0.1:9292/ui`

If something fails:

```bash
docker compose logs --tail=100 turboquant
```

## Maintenance

Machine bootstrap and model maintenance are intentionally separate.

- Change machine-local model paths in `.env`.
- Add/tune model profiles directly in `llama-swap/config.yaml`.
- Update Compose only for container-level settings.
- Rebuild the image only when the TurboQuant/llama.cpp runtime itself changes.

There are no platform-specific profile files and no config-generation step.

## NVIDIA Container Toolkit on Linux

Install the toolkit using the instructions appropriate for your distribution, then configure Docker. A typical setup is:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Confirm Docker sees the GPU before debugging this repository.

## OpenCode

Use the server as an OpenAI-compatible provider with base URL:

```text
http://127.0.0.1:9292/v1
```

The virtual model IDs come directly from `llama-swap/config.yaml` and are discoverable through `/v1/models`.
