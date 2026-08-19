# TurboQuant-Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein privates Repo `turboquant-setup`, das einen TurboQuant+MTP-llama.cpp-Fork (Indras-Mirror/llama.cpp-mtp) klont, auf Windows und Arch-Linux baut und als OpenAI-kompatiblen Server (Port 8080) mit 9b/27b-Profilen betreibt.

**Architecture:** Engine-Swap-Prinzip — `profiles.conf` definiert Fork-URL/-Branch und Modellpfade; `scripts/windows/*.ps1` und `scripts/linux/*.sh` sind dünne Wrapper um Build/Start/Bench. Windows-first (diese Maschine), Linux-Skripte werden geschrieben, aber hier nur syntaktisch geprüft.

**Tech Stack:** cmake, CUDA 13.2 (sm_89), MSVC 2022 / Arch (base-devel, cuda), llama-server (OpenAI-API), PowerShell 7, bash, Hugging Face GGUFs.

## Global Constraints

- Fork primär: `https://github.com/Indras-Mirror/llama.cpp-mtp` (Branch `main`, beim Klonen verifizieren); Fallback: `https://github.com/AtomicBot-ai/atomic-llama-cpp-turboquant` — Wechsel nur über `FORK_URL`/`FORK_BRANCH` in `profiles.conf`
- CUDA-Architektur: `sm_89` (RTX 4070 Ti SUPER); Build: `cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89`
- Modelle in `models/` (gitignored): 9b = `Qwen3.5-9B-Q4_K_M.gguf` (5,68 GB), 27b = `Qwen3.8-27B-UD-Q3_K_XL.gguf` (13,1 GB) + `mtp-Qwen3.8-27B-Q4_0.gguf` (1,37 GB) + `mmproj-BF16.gguf` (optional)
- Port `8080`, Host `127.0.0.1`, gemeinsame Flags `-ngl 99 --flash-attn on --jinja -np 1`
- 9b-Profil: ohne MTP; 27b-Profil: MTP (exakte Flags aus Fork-`MTP.md`/`--help` verifizieren, siehe Task 4)
- Nichts löschen; alle Skripte idempotent (Klon/Build überspringen, wenn vorhanden)
- Commit nach jedem grünen Task; Stil: `feat:`/`fix:`/`docs:`

---

### Task 1: Repo-Grundgerüst

**Files:**
- Create: `LICENSE`, `.gitignore`, `README.md` (Stub), `scripts/common/profiles.conf`, `docs/SETUP.md` (Stub)

**Interfaces:**
- Produces: `profiles.conf` — `KEY=VALUE`-Zeilen, von allen Skripten geparst

- [ ] **Step 1: Grunddateien schreiben**

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

- [ ] **Step 2: Verifizieren + Commit**

Run: `git status` und `Get-Content scripts/common/profiles.conf` — alle Dateien vorhanden.
```bash
git add -A
git commit -m "feat: repo scaffold mit profiles.conf"
```

---

### Task 2: setup.ps1 — Fork klonen + CUDA-Build (Windows)

**Files:**
- Create: `scripts/windows/setup.ps1`

**Interfaces:**
- Consumes: `profiles.conf` (KEY=VALUE, `#`-Kommentare, Pfade relativ zur Repo-Wurzel)
- Produces: `engine/llama.cpp-mtp/build/bin/llama-server.exe` (+ `llama-cli.exe`, `llama-bench.exe`), von Task 3–5 genutzt

- [ ] **Step 1: Skript schreiben**

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}
$engine = Join-Path $Root $conf["ENGINE_DIR"]
$build  = Join-Path $Root $conf["BUILD_DIR"]

if (-not (Test-Path $engine)) {
    git clone --branch $conf["FORK_BRANCH"] $conf["FORK_URL"] $engine
    if ($LASTEXITCODE -ne 0) { throw "git clone fehlgeschlagen" }
} else {
    Write-Host "Engine vorhanden, überspringe Klonen: $engine"
}

if (-not (Test-Path (Join-Path $build "CMakeCache.txt"))) {
    cmake -S $engine -B $build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "cmake configure fehlgeschlagen" }
} else {
    Write-Host "Build-Cache vorhanden, überspringe configure"
}

cmake --build $build --config Release -j --target llama-server llama-cli llama-bench
if ($LASTEXITCODE -ne 0) { throw "cmake build fehlgeschlagen" }

$server = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $server)) { $server = Join-Path $build "bin/llama-server.exe" }
if (-not (Test-Path $server)) { throw "llama-server.exe nicht gefunden unter $build" }
& $server --version
Write-Host "OK: Setup abgeschlossen. Server: $server"
```

- [ ] **Step 2: Skript ausführen**

Run: `pwsh scripts/windows/setup.ps1` (aus der Repo-Wurzel)
Expected: Klonen + Build; Ausgabe von `llama-server --version` (Fork-Version). Kein `throw`.

- [ ] **Step 3: Fork-Doku für MTP/KV-Typen sichern**

Run: `& engine/llama.cpp-mtp/build/bin/Release/llama-server.exe --help 2>&1 | Select-String "cache-type|spec-type|spec-draft"` (Pfad ggf. ohne `Release\`)
Expected: Liste der verfügbaren `-ctk/-ctv`-Typen (u.a. `tbq4_0`, ggf. `planar3_0`/`iso3_0`) und Spec-Flags. Ergebnis in `docs/SETUP.md` unter „Verfügbare KV-Typen" notieren — Grundlage für Task 4.

- [ ] **Step 4: Commit**

```bash
git add scripts/windows/setup.ps1
git commit -m "feat: windows setup.ps1 (Klon + CUDA-Build)"
```

---

### Task 3: start-server.ps1 + 9b-Profil Smoke-Test

**Files:**
- Create: `scripts/windows/start-server.ps1`, `scripts/windows/download-gguf.ps1`

**Interfaces:**
- Consumes: `profiles.conf`; `llama-server.exe` (Task 2)
- Produces: laufender Server auf `http://127.0.0.1:8080/v1` (OpenAI-kompatibel); `models/Qwen3.5-9B-Q4_K_M.gguf`

- [ ] **Step 1: download-gguf.ps1 schreiben**

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$models = Join-Path $Root "models"
New-Item -ItemType Directory -Force -Path $models | Out-Null
$urls = @(
    "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf"
)
foreach ($u in $urls) {
    $f = Join-Path $models ([IO.Path]::GetFileName($u))
    if (Test-Path $f) { Write-Host "Vorhanden: $f"; continue }
    Write-Host "Downloade $u"
    Invoke-WebRequest -UseBasicParsing $u -OutFile $f
}
Write-Host "OK: Modelle in $models"
```

- [ ] **Step 2: 9B-GGUF herunterladen**

Run: `pwsh scripts/windows/download-gguf.ps1`
Expected: `models/Qwen3.5-9B-Q4_K_M.gguf` (5,68 GB) vorhanden.

- [ ] **Step 3: start-server.ps1 schreiben**

```powershell
#!/usr/bin/env pwsh
param([Parameter(Mandatory=$true)][ValidateSet("9b","27b")][string]$Profile)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}
$build = Join-Path $Root $conf["BUILD_DIR"]
$server = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $server)) { $server = Join-Path $build "bin/llama-server.exe" }
$model = Join-Path $Root $conf["MODEL_9B"]
if ($Profile -eq "27b") { $model = Join-Path $Root $conf["MODEL_27B"] }
if (-not (Test-Path $model)) { throw "Modell fehlt: $model" }

$args = @(
    "-m", $model,
    "-ngl", $conf["GPU_LAYERS"],
    "-c", $conf["CTX"],
    "-ctk", $conf["KV_K"],
    "-ctv", $conf["KV_V"],
    "--flash-attn", "on",
    "--jinja",
    "-np", "1",
    "--host", $conf["HOST"],
    "--port", $conf["PORT"]
)
if ($Profile -eq "27b" -and (Test-Path (Join-Path $Root $conf["MTP_DRAFT_27B"]))) {
    $args += "--spec-type", "mtp", "--spec-draft-model", (Join-Path $Root $conf["MTP_DRAFT_27B"]), "--spec-draft-n-max", "3"
}
Write-Host "Starte llama-server (Profil $Profile):"
Write-Host "  $server $($args -join ' ')"
& $server @args
```

- [ ] **Step 4: Server starten (9b) + Health-Check**

Run (separates Terminal oder `Start-Process`): `pwsh scripts/windows/start-server.ps1 -Profile 9b`
Wait: Log zeigt `server is listening on http://127.0.0.1:8080`
Run: `curl.exe -s http://127.0.0.1:8080/v1/models`
Expected: JSON mit dem Modell `Qwen3.5-9B-Q4_K_M.gguf`.

- [ ] **Step 5: Smoke-Chat**

```powershell
$body = '{"model":"Qwen3.5-9B-Q4_K_M.gguf","messages":[{"role":"user","content":"Antworte nur mit: OK"}]}'
curl.exe -s -X POST http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" -d $body
```
Expected: Antwort enthält `"content":"OK"`. Server danach beenden (Ctrl+C / Prozess killen).

- [ ] **Step 6: Commit**

```bash
git add scripts/windows/start-server.ps1 scripts/windows/download-gguf.ps1
git commit -m "feat: start-server.ps1 + 9b-Profil (Smoke-Test grün)"
```

---

### Task 4: 27b-Profil + MTP + Smoke-Test

**Files:**
- Modify: `scripts/windows/start-server.ps1` (KV-Typen/27b-Flags aus Task-2-Step-3-Ergebnis), `scripts/common/profiles.conf` (KV_V für 27b ggf. `tbq4_0`)

**Interfaces:**
- Consumes: `models/Qwen3.8-27B-UD-Q3_K_XL.gguf` (Download läuft beim User, muss fertig sein — kein `.part` mehr), `models/mtp-Qwen3.8-27B-Q4_0.gguf`
- Produces: gemessene 27b-Zahlen für README (tok/s, VRAM)

- [ ] **Step 1: 27B-Download prüfen**

Run: `Get-ChildItem models | Select Name,Length`
Expected: `Qwen3.8-27B-UD-Q3_K_XL.gguf` ohne `.part`-Suffix, ~13,1 GB. Falls `.part` übrig: User informieren, warten.

- [ ] **Step 2: MTP-Flags aus der Fork-Doku verifizieren**

Run: `Get-Content engine/llama.cpp-mtp/MTP.md` (oder `NEXTN.md`, falls vorhanden)
Expected: Bestätigung von `--spec-type mtp` + `--spec-draft-n-max`; prüfen, ob separater Draft (`--spec-draft-model`) oder eingebetteter Head erwartet wird. Falls separate Draft-Modelle nicht unterstützt werden: `--spec-type mtp` mit eingebettetem Head (dann ohne `--spec-draft-model`) — in `start-server.ps1` entsprechend anpassen.

- [ ] **Step 3: KV-Typen auf 27b abstimmen**

Run: `llama-server.exe --help | Select-String "cache-type"` (Ergebnis aus Task 2 Step 3)
Decision: Wenn `tbq4_0` verfügbar → 27b: `-ctk tbq4_0 -ctv tbq4_0`; sonst `q8_0`/`turbo3` aus profiles.conf. Änderung in `start-server.ps1` nur für das 27b-Profil (9b behält profiles.conf-Werte).

- [ ] **Step 4: Server starten (27b) + Smoke-Test**

Run: `pwsh scripts/windows/start-server.ps1 -Profile 27b`
Expected: Log: Modell geladen (VRAM ~13–15 GB), `server is listening`. Dann:
```powershell
$body = '{"model":"Qwen3.8-27B-UD-Q3_K_XL.gguf","messages":[{"role":"user","content":"Antworte nur mit: OK"}]}'
curl.exe -s -X POST http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" -d $body
```
Expected: `"content":"OK"`. Falls OOM/Absturz: kleineren Quant (UD-IQ4_XS 14,3 GB) oder `GPU_LAYERS` reduzieren — Ergebnis in SETUP.md notieren.

- [ ] **Step 5: Commit**

```bash
git add scripts/windows/start-server.ps1 scripts/common/profiles.conf docs/SETUP.md
git commit -m "feat: 27b-Profil mit MTP (Smoke-Test grün)"
```

---

### Task 5: bench.ps1 + VRAM-Veridict

**Files:**
- Create: `scripts/windows/bench.ps1`

**Interfaces:**
- Consumes: `profiles.conf`, `llama-bench.exe` (Task 2)
- Produces: Benchmark-Ausgabe (t/s pp512/tg128) + VRAM-Check vor Start

- [ ] **Step 1: Skript schreiben**

```powershell
#!/usr/bin/env pwsh
param([Parameter(Mandatory=$true)][ValidateSet("9b","27b")][string]$Profile)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}
$build = Join-Path $Root $conf["BUILD_DIR"]
$bench = Join-Path $build "bin/Release/llama-bench.exe"
if (-not (Test-Path $bench)) { $bench = Join-Path $build "bin/llama-bench.exe" }
$model = Join-Path $Root $conf["MODEL_9B"]
if ($Profile -eq "27b") { $model = Join-Path $Root $conf["MODEL_27B"] }
if (-not (Test-Path $model)) { throw "Modell fehlt: $model" }

$vram = (nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | Select-Object -First 1).Trim()
$size = (Get-Item $model).Length / 1GB
Write-Host "VRAM gesamt: ${vram} GB | Modell: $([math]::Round($size,1)) GB"
if ([double]$vram -lt $size) { Write-Warning "Modell groesser als VRAM — erwarte CPU-Offload/Spill. Kleineren Quant oder niedrigeres -ngl erwägen." }

& $bench -m $model -ngl $conf["GPU_LAYERS"] -ctk $conf["KV_K"] -ctv $conf["KV_V"] -c $conf["CTX"] -p 512 -n 128
```

- [ ] **Step 2: Bench 9b + 27b ausführen**

Run: `pwsh scripts/windows/bench.ps1 -Profile 9b`, dann `pwsh scripts/windows/bench.ps1 -Profile 27b`
Expected: Tabelle mit `pp512`/`tg128` in t/s; VRAM-Warnung erscheint bei 27b nicht (13,1 GB < 16 GB), bei 9b auch nicht. Zahlen in README (Abschnitt Benchmarks) festhalten.

- [ ] **Step 3: Commit**

```bash
git add scripts/windows/bench.ps1 README.md
git commit -m "feat: bench.ps1 mit VRAM-Veridict"
```

---

### Task 6: Linux-Skripte (Arch)

**Files:**
- Create: `scripts/linux/setup.sh`, `scripts/linux/start-server.sh`, `scripts/linux/bench.sh`

**Interfaces:**
- Consumes: `profiles.conf` (gleiche Keys); `pacman`-Pakete: `base-devel cmake git python curl` + `cuda` (AUR nicht nötig, cuda ist im core/extra-Repo von Arch)
- Produces: identisches Verhalten wie Windows-Skripte; auf Arch nicht testbar (kein Linux-Zugriff von hier) → nur `bash -n`-Syntaxcheck

- [ ] **Step 1: setup.sh schreiben**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/scripts/common/profiles.conf"
get() { grep -E "^$1=" "$CONF" | head -1 | cut -d= -f2- | tr -d '\r'; }

if ! command -v cmake >/dev/null; then
  echo "Installiere Build-Abhaengigkeiten (sudo noetig):"
  sudo pacman -S --needed --noconfirm base-devel cmake git python curl cuda
fi

ENGINE="$ROOT/$(get ENGINE_DIR)"
BUILD="$ROOT/$(get BUILD_DIR)"
if [ ! -d "$ENGINE" ]; then
  git clone --branch "$(get FORK_BRANCH)" "$(get FORK_URL)" "$ENGINE"
fi
if [ ! -f "$BUILD/CMakeCache.txt" ]; then
  cmake -S "$ENGINE" -B "$BUILD" -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release
fi
cmake --build "$BUILD" -j --target llama-server llama-cli llama-bench
"$BUILD/bin/llama-server" --version
echo "OK: Setup abgeschlossen."
```

- [ ] **Step 2: start-server.sh schreiben**

```bash
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${1:?Usage: start-server.sh <9b|27b>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/scripts/common/profiles.conf"
get() { grep -E "^$1=" "$CONF" | head -1 | cut -d= -f2- | tr -d '\r'; }

BUILD="$ROOT/$(get BUILD_DIR)"
SERVER="$BUILD/bin/llama-server"
MODEL="$ROOT/$(get MODEL_9B)"
if [ "$PROFILE" = "27b" ]; then MODEL="$ROOT/$(get MODEL_27B)"; fi
[ -f "$MODEL" ] || { echo "Modell fehlt: $MODEL" >&2; exit 1; }

ARGS=(-m "$MODEL" -ngl "$(get GPU_LAYERS)" -c "$(get CTX)" -ctk "$(get KV_K)" -ctv "$(get KV_V)" \
      --flash-attn on --jinja -np 1 --host "$(get HOST)" --port "$(get PORT)")
if [ "$PROFILE" = "27b" ] && [ -f "$ROOT/$(get MTP_DRAFT_27B)" ]; then
  ARGS+=(--spec-type mtp --spec-draft-model "$ROOT/$(get MTP_DRAFT_27B)" --spec-draft-n-max 3)
fi
echo "Starte llama-server (Profil $PROFILE):"
echo "  $SERVER ${ARGS[*]}"
exec "$SERVER" "${ARGS[@]}"
```

- [ ] **Step 3: bench.sh schreiben**

```bash
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${1:?Usage: bench.sh <9b|27b>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/scripts/common/profiles.conf"
get() { grep -E "^$1=" "$CONF" | head -1 | cut -d= -f2- | tr -d '\r'; }

BUILD="$ROOT/$(get BUILD_DIR)"
BENCH="$BUILD/bin/llama-bench"
MODEL="$ROOT/$(get MODEL_9B)"
if [ "$PROFILE" = "27b" ]; then MODEL="$ROOT/$(get MODEL_27B)"; fi
[ -f "$MODEL" ] || { echo "Modell fehlt: $MODEL" >&2; exit 1; }

VRAM="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')"
SIZE="$(du -BG "$MODEL" | cut -f1 | tr -d G)"
echo "VRAM gesamt: ${VRAM} GB | Modell: ${SIZE} GB"
if [ "$VRAM" -lt "$SIZE" ]; then echo "WARNUNG: Modell groesser als VRAM."; fi

"$BENCH" -m "$MODEL" -ngl "$(get GPU_LAYERS)" -ctk "$(get KV_K)" -ctv "$(get KV_V)" -c "$(get CTX)" -p 512 -n 128
```

- [ ] **Step 4: Syntax-Check**

Run: `bash -n scripts/linux/setup.sh scripts/linux/start-server.sh scripts/linux/bench.sh` (WSL oder git-bash)
Expected: Keine Ausgabe (Syntax OK). Hinweis in SETUP.md: Arch-Setup-Ablauf (sudo pacman-Befehl läuft im Skript).

- [ ] **Step 5: Commit**

```bash
git add scripts/linux/
git commit -m "feat: linux setup/start/bench (Arch)"
```

---

### Task 7: README final + GitHub privat + push

**Files:**
- Modify: `README.md`, `docs/SETUP.md`

- [ ] **Step 1: README vervollständigen**

Inhalt: Was ist das (TurboQuant+MTP-Fork, 9b/27b-Profile); Quickstart Windows (`pwsh scripts/windows/setup.ps1` → `download-gguf.ps1` → `start-server.ps1 -Profile 9b`); Quickstart Arch (`scripts/linux/setup.sh` → `start-server.sh 9b`); opencode-Provider-Snippet:
```json
{
  "provider": {
    "turbollm": {
      "base_url": "http://127.0.0.1:8080/v1",
      "models": [{ "name": "Qwen3.8-27B-UD-Q3_K_XL.gguf" }]
    }
  }
}
```
(Snippet-Platzhalter passend zur opencode-Version — User trägt es selbst ein); Benchmarks-Tabelle (Zahlen aus Task 5); Troubleshooting (OOM → kleinerer Quant/ngl; Port belegt; Engine-Swap via FORK_URL).

- [ ] **Step 2: GitHub-Repo anlegen + pushen**

```bash
gh repo create turboquant-setup --private --source . --push
```
Expected: Repo `TM/turboquant-setup` (privat) mit allen Commits.

- [ ] **Step 3: Finale Verifikation**

Run: `git log --oneline` (7+ Commits), `gh repo view TM/turboquant-setup` — privat, alle Dateien da.
Hinweis an User: Auf dem Arch-System `git clone https://github.com/TM/turboquant-setup` + `scripts/linux/setup.sh` + Modelle nach `models/` legen.

---

## Self-Review-Notizen

- Spec-Abdeckung: Engine-Wahl (Task 2 Klonen/Build, Task 4 MTP), Profile 9b/27b (Task 3/4), Verifikation (Tasks 3/5), Linux (Task 6), opencode-Snippet (Task 7), GitHub privat (Task 7), Engine-Swap (profiles.conf, Task 1)
- MTP-Flags: in Task 4 mit Verifikations-Schritt gegen Fork-Doku abgesichert (bekannter Stand `--spec-type mtp --spec-draft-n-max 3`)
- KV-Typen: Task 4 Step 3 entscheidet tbq4_0 vs. q8_0/turbo3 anhand von `--help`
- 27B-Download: `.part`-Status als Blocker in Task 4 Step 1 berücksichtigt
- Keine Platzhalter: alle Steps enthalten konkrete Befehle/Code