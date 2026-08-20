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
llama-swap/config.yaml
        |
        v
/v1/models
        |
        | inference request selects a model ID
        v
TurboQuant llama-server starts on demand
```

The Docker image contains the engine and gateway, not the model weights.

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

Always use the container path in `llama-swap/config.yaml`.

If a user supplies a model file outside the configured `MODELS_DIR`, decide explicitly whether to change the local `MODELS_DIR` arrangement or place the file in the canonical model directory. Do not silently duplicate large model files.

## 3. Add a llama-swap profile

Edit:

```text
llama-swap/config.yaml
```

A simple model profile can look like this:

```yaml
models:
  "my-model-128k":
    name: "My Model — 128K"
    description: "128K profile using TurboQuant KV cache."
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

Match the surrounding file's indentation and schema.

### Direct path vs macro

For a single profile, prefer a direct container path:

```text
-m "/models/MyModel-Q4_K_M.gguf"
```

Use a macro/environment variable only when the same physical GGUF is deliberately reused by several profiles and the indirection makes the configuration clearer.

For example, one 27B GGUF can back several virtual profiles with different context or MTP settings. Those profiles still use one physical file.

## 4. Runtime settings belong in the YAML

Per-model runtime choices belong in `llama-swap/config.yaml`, including:

- context size (`-c`)
- KV cache types (`-ctk`, `-ctv`)
- `--fit` and fitting target
- flash attention
- parallelism
- MTP/speculative decoding
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

The gateway is configured to watch its config file. If it is already running, a normal YAML profile edit should be picked up without rebuilding the image.

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

Do not add the draft model to the Docker image.

## Checklist for agents

When asked to install a model, determine:

1. Is the GGUF already available locally?
2. What host directory is currently used as `MODELS_DIR`?
3. What exact filename will appear under `/models`?
4. What virtual model ID should be exposed?
5. What context/KV/MTP/runtime settings are desired?
6. Can the change be done entirely in `llama-swap/config.yaml`? For a normal model addition, the answer should be yes.
7. Does `/v1/models` show the new ID after the edit?

If an action would trigger a download, CUDA build, CI job, benchmark, or other expensive work, explain that consequence and obtain explicit approval first unless the user already requested that exact action.
