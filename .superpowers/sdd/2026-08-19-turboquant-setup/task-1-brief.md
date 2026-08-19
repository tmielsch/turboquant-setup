# Task 1 Brief: Repo-Grundgerüst

**Files:**
- Create: `LICENSE`, `.gitignore`, `README.md` (Stub), `scripts/common/profiles.conf`, `docs/SETUP.md` (Stub)

**Interfaces:**
- Produces: `profiles.conf` — `KEY=VALUE`-Zeilen, von allen Skripten geparst

## Step 1: Grunddateien schreiben

`LICENSE` — MIT, Copyright 2026 TM.

`.gitignore`:
```
models/
engine/
build/
*.part
```

`scripts/common/profiles.conf`:
```ini
FORK_URL=https://github.com/Indras-Mirror/llama.cpp-mtp
FORK_BRANCH=main
ENGINE_DIR=engine/llama.cpp-mtp
BUILD_DIR=engine/build
PORT=8080
HOST=127.0.0.1
GPU_LAYERS=99
CTX=32768
KV_K=q8_0
KV_V=turbo3

MODEL_9B=models/Qwen3.5-9B-Q4_K_M.gguf
MODEL_27B=models/Qwen3.8-27B-UD-Q3_K_XL.gguf
MTP_DRAFT_27B=models/mtp-Qwen3.8-27B-Q4_0.gguf
MMPROJ=models/mmproj-BF16.gguf
```

`README.md` (Stub): Titel, ein Satz, Verweis auf docs/SETUP.md.
`docs/SETUP.md` (Stub): Überschrift + „In Arbeit".

## Step 2: Verifizieren + Commit

Run: `git status` und `Get-Content scripts/common/profiles.conf` — alle Dateien vorhanden.
```bash
git add -A
git commit -m "feat: repo scaffold mit profiles.conf"
```