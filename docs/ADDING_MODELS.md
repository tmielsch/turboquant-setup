# Adding and Tuning Models

The live model/runtime configuration is the machine-local file:

```text
llama-swap/config.yaml
```

It is gitignored. Edit it directly. The repository tracks only `llama-swap/config.example.yaml` as a starter baseline for new machines.

There is no generator, secondary model registry, or automatic synchronization between example and live config.

## Mental model

```text
tracked repository baseline
llama-swap/config.example.yaml
        |
        | copied ONCE on first setup
        v
local live config (gitignored)
llama-swap/config.yaml
        |
        | references
        v
/models inside container
        |
        v
host GGUF directory (MODELS_DIR)
```

At runtime:

```text
/v1/models
    |
    | request selects virtual model ID
    v
TurboQuant llama-server starts on demand
```

## 1. Put or reuse the GGUF in `MODELS_DIR`

`.env` selects the host directory:

```dotenv
MODELS_DIR=/path/to/models
```

Inside the container this directory is always `/models`.

If the GGUF already exists, reuse it. Do not duplicate or redownload large model files just to create another runtime profile.

## 2. Add a profile directly to local `llama-swap/config.yaml`

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

The section key is the model ID exposed through the OpenAI-compatible API.

## 3. Multiple profiles can use one GGUF

This is a core llama-swap use case. The same physical GGUF can have several virtual IDs with different context/KV/MTP/runtime flags. No extra abstraction is needed.

Example:

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

## Runtime settings belong in the local profile

Put per-model `llama-server` options directly in each profile's `cmd` block, including context, K/V cache, fit/offload, Flash Attention, MTP/speculative decoding, MoE settings, sampling flags, and experimental TurboQuant options.

When llama.cpp/TurboQuant adds a new runtime flag, use it directly. Do not extend a custom schema or generator.

## Common KV cache choices

Typical profiles worth benchmarking include:

```text
q8_0 / turbo4   conservative asymmetric
q8_0 / turbo3   quality-oriented asymmetric
q8_0 / turbo2   stronger V compression
turbo2 / turbo2 maximum compression
```

Do not assume one global KV choice is optimal for every model or context size. Higher K precision can improve quality but may consume enough VRAM to force weight offload at very long contexts.

## MTP / speculative decoding

MTP packaging differs between GGUFs. Some contain the relevant MTP tensors in the main GGUF; others use a separate draft GGUF.

Configure the exact flags required by that GGUF directly in the relevant local profile. Do not force one MTP packaging style through a repository abstraction.

Examples may use:

```text
--spec-type draft-mtp
```

or, when a separate draft file is actually required:

```text
--spec-type draft-mtp
--spec-draft-model /models/Some-MTP-Draft.gguf
```

## Repository baseline is optional

A local model change does **not** have to be copied back into `config.example.yaml` or pushed to Git.

Only update `config.example.yaml` when you intentionally want future fresh installations to start with that profile. Differences between local config and the example are normal and should not be treated as drift.

## Migrating from the old registry

For an existing machine, prefer preserving the current live `llama-swap/config.yaml` rather than regenerating it from `models.conf`.

After the repository refactor, keep that YAML as the local gitignored runtime config and retire the old registry. The old INI file is not a new source of truth.

## Apply and validate

llama-swap runs with config watching enabled, so a valid edit may reload automatically. If needed:

```bash
docker compose restart turboquant
```

Then check discovery:

```bash
curl http://127.0.0.1:9292/v1/models
```

Model discovery should not load weights into VRAM.

If there is a config error:

```bash
docker compose logs --tail=100 turboquant
```

## What not to do

For a normal local model/profile change, do **not**:

- rebuild the Docker image
- edit `docker/Dockerfile.cuda`
- edit GitHub Actions workflows
- edit the tracked `config.example.yaml` unless the user explicitly wants the repository baseline changed
- create another registry or generated copy of `config.yaml`
- copy `config.example.yaml` over an existing local config
- rewrite unrelated model entries
- copy the same GGUF for every context profile

## Agent checklist

1. Determine whether the task is a **local config change** or an intentional **repository baseline change**.
2. For local work, read the current local `llama-swap/config.yaml` first.
3. Add/change only the relevant YAML block.
4. Preserve unrelated local entries exactly.
5. Do not push the local config merely because it changed.
6. Check `/v1/models` and logs if the gateway is running.
7. Do not trigger downloads, builds, benchmarks, or large inference unless requested.
