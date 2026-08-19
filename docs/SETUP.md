# Setup

> **Hinweis:** Der empfohlene Weg ist das vorgebaute Docker-Image
> (siehe README). Dieser Abschnitt beschreibt die native Installation für
> Entwicklung und Debugging - sie kompiliert die Engine aus dem Quellcode
> (CUDA/CMake) und dauert deutlich länger.

## Gemeinsame Architektur

Windows und CachyOS/Linux verwenden dieselbe `scripts/common/profiles.conf` und dieselbe `llama-swap/config.yaml`. `llama-swap` läuft dauerhaft auf `127.0.0.1:9292`; ein Modell wird erst geladen, wenn Hermes/OpenCode eine der virtuellen Model-IDs anfordert.

Unter Docker wird `llama-swap/config.yaml` automatisch aus `models.conf` generiert (`bash scripts/generate-config.sh`); Modelle werden über `models.conf` bzw. `scripts/add-model.sh` verwaltet - Details in `docs/MODELS.md`. Die nativen Skripte hier setzen die Pfade über `profiles.conf` und Umgebungsvariablen.

### Verfügbare Model-IDs

- `qwen3.5-9b-32k`
- `qwen3.8-27b-200k`
- `qwen3.8-27b-250k`
- `qwen3.8-27b-200k-mtp`
- `qwen3.8-27b-250k-mtp`

Die 27B-Varianten nutzen dieselbe GGUF-Datei mit unterschiedlichen Runtime-Parametern.

## Windows

```powershell
.\scripts\windows\setup.ps1
winget install llama-swap
.\scripts\windows\start-gateway.ps1
```

Optionaler Autostart:

```powershell
.\scripts\windows\install-autostart.ps1
```

## CachyOS / Arch Linux

Build-Abhängigkeiten, falls nötig:

```bash
sudo pacman -S --needed base-devel git cmake cuda
```

Engine bauen:

```bash
bash scripts/linux/setup.sh
```

`llama-swap` ist offiziell als Linux-Release-Binary verfügbar oder kann mit Homebrew installiert werden:

```bash
brew tap mostlygeek/llama-swap
brew install llama-swap
```

Gateway starten:

```bash
bash scripts/linux/start-gateway.sh
```

Autostart als systemd-User-Service:

```bash
bash scripts/linux/install-autostart.sh
```

Status und Logs:

```bash
systemctl --user status turboquant-gateway.service
journalctl --user -u turboquant-gateway.service -f
```

Optionaler Start bereits vor dem Login:

```bash
sudo loginctl enable-linger "$USER"
```

## API

Auf beiden Betriebssystemen:

- API: `http://127.0.0.1:9292/v1`
- Model Discovery: `http://127.0.0.1:9292/v1/models`
- Web UI: `http://127.0.0.1:9292/ui`

## Direkter Debug-Start

Windows:

```powershell
.\scripts\windows\start-server.ps1 27b-200k
```

Linux:

```bash
bash scripts/linux/start-server.sh 27b-200k
```

Der direkte Start ist nur für Benchmarks/Troubleshooting gedacht. Im Alltag sollte ausschließlich `llama-swap` laufen.
