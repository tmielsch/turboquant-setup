# TurboQuant Setup

Lokales Qwen/TurboQuant-Setup für sehr lange Kontexte auf 16 GB VRAM.

## Ziel

- RTX 4070 Ti SUPER 16 GB
- Qwen3.8-27B `UD-Q3_K_XL`
- mindestens 200K Context, 250K als Max-Profil
- asymmetrischer TurboQuant-KV-Cache: `q8_0` für K, `turbo2` für V
- TheTom `llama-cpp-turboquant` als Inferenz-Engine
- `llama-swap` als dauerhaft laufender OpenAI-kompatibler Gateway
- **kein Modell beim Boot geladen**; die ausgewählte Variante wird erst beim API-Request gestartet
- Windows und CachyOS/Linux verwenden dieselben Model-IDs und dieselbe Gateway-Konfiguration
- Hermes/OpenCode wählen Varianten einfach über den Model-ID

## Empfohlen: fertiges Docker-Image

Der normale Installationsweg soll **nicht mehr lokal kompilieren**. GitHub Actions baut CUDA + TurboQuant zentral und veröffentlicht das fertige Image als:

```text
ghcr.io/tmielsch/turboquant-setup:cuda
```

Nach dem ersten veröffentlichten Build reicht auf einem NVIDIA-Docker-Host:

```bash
git clone https://github.com/tmielsch/turboquant-setup.git
cd turboquant-setup
cp .env.example .env
# MODELS_DIR in .env bei Bedarf anpassen

docker compose pull
docker compose up -d
```

Danach:

- API: `http://127.0.0.1:9292/v1`
- Model Discovery: `http://127.0.0.1:9292/v1/models`
- Web UI: `http://127.0.0.1:9292/ui`

Der Container startet nur `llama-swap`. **Kein LLM wird beim Containerstart geladen.** Erst ein Request von Hermes/OpenCode startet den passenden TurboQuant `llama-server` im Container.

Die Modelle selbst sind **nicht im Image**. `MODELS_DIR` wird nur nach `/models` gemountet, damit dieselben GGUFs unabhängig vom Betriebssystem weiterverwendet werden können.

### Host-Anforderungen

**CachyOS / Linux:** Docker + funktionierender NVIDIA Container Runtime/Toolkit.

**Windows:** Docker Desktop mit WSL2 und funktionierendem NVIDIA-GPU-Passthrough.

Der eigentliche CUDA-/CMake-Build findet in beiden Fällen nicht auf dem Zielrechner statt.

## Architektur

```text
Hermes / OpenCode / andere OpenAI-Clients
                 |
                 |  http://127.0.0.1:9292/v1
                 v
            llama-swap
                 |
                 | model=qwen3.8-27b-250k
                 v
      TheTom llama-server (on demand)
                 |
                 +-- Qwen3.8-27B GGUF (nur einmal auf Platte)
                 +-- Context/KV/MTP je nach virtueller Model-ID
```

`llama-swap` veröffentlicht die Varianten über `/v1/models`, lädt sie bei Bedarf und beendet beim Wechsel die vorherige Variante.

## Verfügbare Model-IDs

| Model-ID | Context | KV Cache | MTP |
|---|---:|---|---|
| `qwen3.5-9b-32k` | 32K | `q8_0` K / `turbo3` V | nein |
| `qwen3.8-27b-200k` | 200K | `q8_0` K / `turbo2` V | nein |
| `qwen3.8-27b-250k` | 250K | `q8_0` K / `turbo2` V | nein |
| `qwen3.8-27b-200k-mtp` | 200K | `q8_0` K / `turbo2` V | ja |
| `qwen3.8-27b-250k-mtp` | 250K | `q8_0` K / `turbo2` V | ja |

Alle 27B-Varianten referenzieren **dieselbe** `Qwen3.8-27B-UD-Q3_K_XL.gguf`. Es werden keine Modellkopien angelegt.

## Hermes

Hermes verwendet auf Windows und Linux denselben benannten Custom Provider `turboquant` mit `http://127.0.0.1:9292/v1`. Die per-model Context-Längen werden explizit mit 200K bzw. 250K hinterlegt.

In einer laufenden Session z. B.:

```text
/model custom:turboquant:qwen3.8-27b-200k
/model custom:turboquant:qwen3.8-27b-250k
/model custom:turboquant:qwen3.8-27b-200k-mtp
```

Die vollständige Hermes-Konfiguration steht in [docs/HERMES.md](docs/HERMES.md).

## OpenCode

OpenCode bekommt denselben OpenAI-kompatiblen Provider:

```text
baseURL = http://127.0.0.1:9292/v1
```

Die Model-Auswahl kommt aus `/v1/models`; ein Wechsel des Model-IDs triggert automatisch den passenden llama-server.

## Native Installation (Fallback / Entwicklung)

Falls der Container selbst entwickelt oder ein Fork lokal getestet werden soll, bleiben die nativen Skripte erhalten.

### Windows

```powershell
.\scripts\windows\setup.ps1
winget install llama-swap
.\scripts\windows\start-gateway.ps1
```

Optionaler Autostart:

```powershell
.\scripts\windows\install-autostart.ps1
```

### CachyOS / Arch Linux

```bash
sudo pacman -S --needed base-devel git cmake cuda
bash scripts/linux/setup.sh
bash scripts/linux/start-gateway.sh
```

Optionaler Autostart:

```bash
bash scripts/linux/install-autostart.sh
```

## Direkter llama-server Start

Nur für Debugging/Benchmarks:

```powershell
.\scripts\windows\start-server.ps1 27b-200k
```

```bash
bash scripts/linux/start-server.sh 27b-200k
```

## Container-Build

`docker/Dockerfile.cuda` kompiliert den aktuellen TheTom-Branch und legt `llama-swap` darüber. `.github/workflows/docker-cuda.yml` validiert den Build in Pull Requests und veröffentlicht nach Merge auf `main` automatisch das fertige `:cuda`-Image nach GHCR.

`.dockerignore` schließt `models/`, lokale Engine-Builds und GGUFs explizit aus dem Build-Kontext aus.

## Engine

Aktuell: `TheTom/llama-cpp-turboquant`, Branch `feature/turboquant-kv-cache`.
