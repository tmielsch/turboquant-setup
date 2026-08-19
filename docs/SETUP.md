# Setup

In Arbeit

## Verfügbare KV-Typen

Extrahiert aus `llama-server --help` (Fork `Indras-Mirror/llama.cpp-mtp`, Branch `feature/dsv4-tbq4-native`, Commit `f48a4e179`).

`-ctk` / `-ctv` (KV-Cache-Typen K und V):

```
f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1, tbq3_0, tbq4_0, planar3_0, iso3_0, planar4_0, iso4_0
```

`-ctkd` / `-ctvd` (Draft-Modell KV-Cache): gleiche Liste wie oben.

`--spec-type` (Speculative-Decoding-Modi):

```
none, draft-simple, draft-eagle3, draft-mtp, draft-dflash, draft-dspark, ngram-simple, ngram-map-k, ngram-map-k4v, ngram-mod, ngram-cache
```

Wichtige Spec-Flags (für MTP-Setup):

- `--spec-draft-model, -md, --model-draft FNAME` — Draft-Modell (z. B. mtp-Qwen3.8-27B-Q4_0.gguf)
- `--spec-draft-n-max N` — Anzahl Draft-Tokens (Default: 3)
- `--spec-draft-n-min N` — Minimum Draft-Tokens
- `--spec-draft-type-k/-v` (`-ctkd/-ctvd`) — KV-Typ des Draft-Modells
- `--spec-draft-ngl, -ngld, --gpu-layers-draft N` — GPU-Layer des Draft-Modells
- `--spec-draft-device, -devd` — Devices für Draft
- `--spec-draft-n-cpu-moe, -ncmoed` — CPU-MoE für Draft
- `--spec-draft-p-split` / `--spec-draft-p-min` — Draft-Wahrscheinlichkeit (greedy)
