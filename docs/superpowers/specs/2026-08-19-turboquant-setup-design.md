# TurboQuant-Setup — Design

Datum: 2026-08-19
Status: Entwurf (User-Review ausstehend)

## Ziel

Ein privates Setup-Repo `turboquant-setup`, das einen TurboQuant-llama.cpp-Fork von GitHub klont, baut und als OpenAI-kompatiblen Server (llama-server) startet — nachhaltig auf **Windows (PowerShell)** und **Arch-Linux (bash)**, sodass opencode über einen Provider-Eintrag (baseURL) darauf zugreifen kann.

Modelle:
- **9b-Profil**: Qwen3.5-9B (Q4_K_M) — für Setup-Smoke-Test und Alltag
- **27b-Profil**: Qwen3.8-27B (UD-Q3_K_XL, 13,1 GB) — Ziel: annehmbare Token-Raten auf 16-GB-GPU

## Kontext / Erkenntnisse

- Hardware: RTX 4070 Ti SUPER 16 GB, Windows mit vollständiger Toolchain (git 2.54, cmake 4.3.2, CUDA 13.2, VS2022, Node 26, Python 3.14)
- Dual-Boot: Arch-basierte Linux-Distro
- TurboQuant = llama.cpp-Fork mit Low-Bit-KV-Cache (`turbo2/3/4`, 2–4 Bit) und Gewichts-Quants (TQ3/TQ4_1S)
- Video-Referenz (27B auf 16-GB-Karte): FP16-KV 39,6 GB → lädt nicht; Q4-KV ~13 GB → 4,5 tok/s (27/64 Layer); `turbo4`-KV → 45/64 Layer, Prefill ~700 tok/s; `turbo2`-KV → 62/64 Layer, ~24 tok/s
- MTP (Multi-Token Prediction): für Qwen3.8-27B upstream via `--spec-type draft-mtp`; Benchmark (RTX 5090): +1,81× Durchsatz bei n=3, verlustfrei; separater MTP-Draft-GGUF (`mtp-Qwen3.8-27B-Q4_0.gguf`, 1,37 GB) von unsloth
- 16-GB-Realität: UD-Q3_K_XL (13,1 GB) + KV-Cache passt; ~46 tok/s mit MTP-Tuning (Quelle: codersera-Guide, 2026-08)

## Engine-Wahl

- **Primär: Indras-Mirror/llama.cpp-mtp** — TurboQuant (TBQ4) + fused Flash-Attention + MTP + RotorQuant + Tensor-Sharing; höchste gemessene Werte (82–179 tok/s auf Qwen3.6-27B, 262K Context auf 24 GB)
- **Fallback: AtomicBot-ai/atomic-llama-cpp-turboquant** — TurboQuant-KV + NextN/MTP (Qwen3.6-Familie), falls Qwen3.8-27B (qwen35-Architektur, DeltaNet) auf dem Primär-Fork nicht sauber läuft
- **Engine-Swap als Design-Prinzip**: `FORK_URL`/`FORK_BRANCH` als Variablen in `profiles.conf` — Wechsel ohne Skript-Umbau
- Testreihenfolge beim Implementieren: 9B-Smoke-Test auf Primär-Fork → 27B-Test → bei Problemen Fallback; Ergebnis im README dokumentieren

## Repo-Struktur

```
turboquant-setup/
├── README.md                  # Kurzanleitung, opencode-Provider-Snippet
├── LICENSE                    # MIT
├── scripts/
│   ├── windows/
│   │   ├── setup.ps1          # Klonen + cmake-Build (CUDA 13.2, VS2022)
│   │   ├── start-server.ps1   # llama-server mit Profil (9b/27b)
│   │   └── bench.ps1          # llama-bench + VRAM-Veridict
│   ├── linux/
│   │   ├── setup.sh           # Arch: base-devel, cmake, cuda, Klonen + Build
│   │   ├── start-server.sh
│   │   └── bench.sh
│   └── common/
│       └── profiles.conf      # zentrale Flag-/Modell-Definitionen
├── models/                    # GGUF-Ablage (gitignored)
└── docs/
    └── SETUP.md               # Anleitungen Windows + Arch, Troubleshooting
```

## Profile (profiles.conf)

| Profil | Modell | Quant | KV (ctk/ctv) | Context | MTP |
|---|---|---|---|---|---|
| 9b | Qwen3.5-9B | Q4_K_M (~6 GB) | `q8_0`/`turbo3` (sicher), `turbo2` (aggressiv) | 32K | ohne (MTP-Head nur im 27b-Profil; 9B dient dem Setup-Test) |
| 27b | Qwen3.8-27B | UD-Q3_K_XL (13,1 GB) | `q8_0`/`turbo2` (Video: 24 tok/s), `turbo3` konservativ | 32K–256K skalierbar | `--spec-type draft-mtp --spec-draft-n-max 3` + Draft-GGUF |

Gemeinsame Flags: `-ngl 99 --flash-attn on --jinja --host 127.0.0.1 --port 8080`
Vision (optional): `--mmproj mmproj-BF16.gguf`

Modelle im Ordner `models/` — Pfade relativ, per Parameter überschreibbar.

## Verifikation

- `setup`: Build-Erfolg + `llama-server --version`; klare Fehlermeldung bei fehlendem CUDA-Toolkit
- `start`: Health-Check `curl /v1/models`; Smoke-Chat via `/v1/chat/completions`
- `bench`: `llama-bench` (pp512/tg128) + VRAM-Veridict vor dem Laden (Warnung bei OOM-Risiko)

## Fehlerbehandlung

- Build-Fehler (CUDA nicht gefunden) → Hinweis + Option CPU-only-Build
- OOM beim Laden → Veridict-Warnung vorab, Empfehlung kleinerer Quant
- Port belegt → klare Meldung mit laufendem Prozess
- Fork wechseln → `FORK_URL`/`FORK_BRANCH` in profiles.conf ändern, setup erneut ausführen

## Implementierungsreihenfolge

1. Windows: Repo anlegen (README, LICENSE, .gitignore), Fork klonen, Build (9b-Profil), Smoke-Test 9B
2. Windows: 27b-Profil, Download-Skripte, Smoke-Test 27B (inkl. MTP + turbo2-KV), Bench
3. Linux (Arch): setup.sh/start-server.sh/bench.sh schreiben (kann auf Windows nicht getestet werden → Doku im SETUP.md)
4. opencode-Provider-Snippet im README
5. GitHub privat anlegen, pushen