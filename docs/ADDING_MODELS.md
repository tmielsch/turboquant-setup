# Adding and Tuning Models

This repository intentionally has one model/runtime configuration file:

```text
llama-swap/config.yaml
```

Edit it directly. There is no generator and no secondary model registry.

## Mental model

```text
host GGUF directory (MODELS_DIR)
        |
        | bind-mounted read-only
        v
/models inside the container
        |
        | referenced directly by
        v
llama-swap/config.yaml
        |
        v
/v1/models
        |
        | request selects virtual model ID
        v
TurboQuant llama-server starts on demand
```

The Docker image contains the engine and gateway, not the model weights.

## 1. Put or reuse the GGUF in `MODELS_DIR`

`.env` selects the host directory:

```dotenv
MODELS_DIR=/path/to/models
```

Inside the container this directory is always `/models`.

For example:

```text
host:      /mnt/llm/Qwen3.8-27B-Ridge.gguf
container: /models/Qwen3.8-27B-Ridge.gguf
```

If the file already exists, reuse it. Do not duplicate or redownload large model files just to add another runtime profile.

## 2. Add a profile directly to `llama-swap/config.yaml`

Example:

```yaml
models:
  "ridge-64k-quality":
    name: "Qwen3.8 27B Ridge - 64K Quality"
    description: "64K profile with higher-precision K cache."
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

The section key (`ridge-64k-quality`) is the model ID exposed through the OpenAI-compatible API.

## 3. Multiple profiles can use one GGUF

This is the main purpose of llama-swap in this repository. You do not need extra GGUF copies or a custom registry.

For example, the same file can have a long-context profile:

```yaml
  "ridge-250k-fast":
    name: "Qwen3.8 27B Ridge - 250K Fast"
    description: "250K profile prioritizing KV size and GPU residency."
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

OpenCode/Hermes can then select either virtual model ID even though both use the same weights.

## Runtime settings belong in the profile

Put per-model `llama-server` options directly in the profile's `cmd` block, including:

- `-c` — context size
- `-ctk`, `-ctv` — K/V cache types
- `-fit`, `-fitt` — fitting/offload behavior
- `--flash-attn`
- MTP/speculative decoding flags
- MoE cache/CPU-MoE flags
- sampling or anti-loop flags
- model-specific experimental TurboQuant options

This is intentionally flexible: when llama.cpp/TurboQuant adds a new runtime flag, it can be used immediately without extending a custom config schema or generator.

## Common KV cache choices

The TurboQuant fork supports standard llama.cpp cache formats as well as TurboQuant formats. K and V can be configured independently.

Typical profiles worth benchmarking include:

```text
q8_0 / turbo4   conservative asymmetric
q8_0 / turbo3   quality-oriented asymmetric
q8_0 / turbo2   stronger V compression
 turbo2 / turbo2 maximum compression
```

Do not assume one global KV choice is optimal for every model or context size. A higher-precision K cache can improve quality but also consume enough VRAM to force weight offload, especially at very long context.

## MTP / speculative decoding

MTP packaging differs between GGUFs. Some models contain the relevant MTP tensors in the main GGUF; others use a separate draft GGUF.

Therefore configure the exact `llama-server` flags required by that GGUF directly in the relevant profile. Do not assume every MTP setup needs a separate file and do not add a repository abstraction that forces one packaging style.

Examples may use flags such as:

```text
--spec-type draft-mtp
```

or, when an actual separate draft GGUF is required:

```text
--spec-type draft-mtp
--spec-draft-model /models/Some-MTP-Draft.gguf
```

Verify support against the engine revision and the model's metadata/readme before enabling it.

## Apply and validate

The container runs llama-swap with config watching enabled, so a valid edit may reload automatically. If needed, restart only the existing container:

```bash
docker compose restart turboquant
```

Then check model discovery:

```bash
curl http://127.0.0.1:9292/v1/models
```

Model discovery should not load weights into VRAM.

If there is a config error:

```bash
docker compose logs --tail=100 turboquant
```

Do not run an inference request or benchmark merely to validate that the model ID is registered unless that test was explicitly requested.

## What not to do

For a normal model/profile change, do **not**:

- rebuild the Docker image
- edit `docker/Dockerfile.cuda`
- edit GitHub Actions workflows
- create another registry or generated copy of `config.yaml`
- rewrite unrelated model entries
- copy the same GGUF for every context profile

## Agent checklist

When adding or tuning a model:

1. Read the current `llama-swap/config.yaml` first.
2. Identify the existing GGUF path under the mounted `/models` tree.
3. Decide the virtual model ID and runtime flags.
4. Add or change only the relevant YAML block.
5. Preserve unrelated entries exactly.
6. Check `/v1/models` and logs if the gateway is running.
7. Do not trigger downloads, builds, benchmarks, or large inference unless requested.
