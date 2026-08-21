# Setup

This repository provides a reusable Docker/runtime baseline. The live model configuration is intentionally machine-local.

## Architecture

There are only two runtime layers:

1. **llama-swap** — persistent OpenAI-compatible gateway on port `9292`.
2. **TurboQuant llama-server** — child process started on demand for the selected virtual model ID.

Configuration state is split deliberately:

- `llama-swap/config.example.yaml` — tracked repository baseline for new machines.
- `llama-swap/config.yaml` — local live configuration, gitignored, never automatically overwritten.
- `.env` — local host path settings such as `MODELS_DIR`.

There is no config generator or synchronization step between the example and the live config.

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
cp llama-swap/config.example.yaml llama-swap/config.yaml
```

Only perform the copies when those local files do not already exist. They are initialization steps, not update commands.

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

## Migrating an older checkout

If an existing installation already has a working `llama-swap/config.yaml`, preserve that file before switching branches or pulling the refactor:

```bash
cp llama-swap/config.yaml llama-swap/config.yaml.backup
```

After the update, keep/restore that YAML as `llama-swap/config.yaml`. Do **not** regenerate it from the old `models.conf` during migration.

Once the new `.gitignore` is present, the live YAML is machine-local and future Git updates do not touch it.

## Existing machine / repository updates

A normal `git pull` updates Docker/runtime files and the tracked `config.example.yaml`, but does **not** touch your gitignored `llama-swap/config.yaml`.

Do not copy the example over your existing config after an update. If the repository baseline gains an interesting profile, manually copy only the relevant block into your local config if you want it.

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

- Add/tune local model profiles directly in `llama-swap/config.yaml`.
- Change machine-local model paths in `.env`.
- Edit `config.example.yaml` only when intentionally changing the repository's bootstrap baseline for future machines.
- Update Compose only for container-level settings.
- Rebuild the image only when the TurboQuant/llama.cpp runtime itself changes.

There are no platform-specific model registries and no config-generation step.

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

The virtual model IDs come from the machine-local `llama-swap/config.yaml` and are discoverable through `/v1/models`.
