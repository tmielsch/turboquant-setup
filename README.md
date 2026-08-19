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

`llama-swap` veröffentlicht die Varianten über `/v1/models`, lädt sie bei Bedarf und beendet beim Wechsel die vorherige Variante. Die Web-Oberfläche ist unter `http://127.0.0.1:9292/ui` erreichbar.

## Verfügbare Model-IDs

| Model-ID | Context | KV Cache | MTP |
|---|---:|---|---|
| `qwen3.5-9b-32k` | 32K | `q8_0` K / `turbo3` V | nein |
| `qwen3.8-27b-200k` | 200K | `q8_0` K / `turbo2` V | nein |
| `qwen3.8-27b-250k` | 250K | `q8_0` K / `turbo2` V | nein |
| `qwen3.8-27b-200k-mtp` | 200K | `q8_0` K / `turbo2` V | ja |
| `qwen3.8-27b-250k-mtp` | 250K | `q8_0` K / `turbo2` V | ja |

Alle 27B-Varianten referenzieren **dieselbe** `Qwen3.8-27B-UD-Q3_K_XL.gguf`. Es werden keine Modellkopien angelegt.

## Windows Setup

### 1. TurboQuant Engine bauen

```powershell
.\scripts\windows\setup.ps1
```

### 2. llama-swap einmalig installieren

```powershell
winget install llama-swap
```

Alternativ kann das einzelne Binary von den llama-swap Releases installiert werden.

### 3. Gateway starten

```powershell
.\scripts\windows\start-gateway.ps1
```

### 4. Optional: Autostart beim Windows-Login

```powershell
.\scripts\windows\install-autostart.ps1
```

## CachyOS / Arch Linux

Die Linux-Seite verwendet dieselbe `scripts/common/profiles.conf` und dieselbe `llama-swap/config.yaml` wie Windows.

### 1. Build-Abhängigkeiten

Das Setup prüft `git`, `cmake` und `nvcc`. Falls etwas fehlt:

```bash
sudo pacman -S --needed base-devel git cmake cuda
```

### 2. TurboQuant Engine bauen

```bash
bash scripts/linux/setup.sh
```

Es wird derselbe TheTom-Fork für CUDA `sm_89` gebaut wie unter Windows.

### 3. llama-swap installieren

Offiziell verfügbar als Linux-Release-Binary oder via Homebrew:

```bash
brew tap mostlygeek/llama-swap
brew install llama-swap
```

Das Release-Binary kann stattdessen einfach als `llama-swap` in einen Ordner im `$PATH` gelegt werden.

### 4. Gateway starten

```bash
bash scripts/linux/start-gateway.sh
```

Danach auf beiden Betriebssystemen identisch:

- API: `http://127.0.0.1:9292/v1`
- Model Discovery: `http://127.0.0.1:9292/v1/models`
- Web UI: `http://127.0.0.1:9292/ui`

Beim Gateway-Start wird **kein Modell geladen**. Erst ein Request mit z. B. `model: qwen3.8-27b-250k` startet den dazugehörigen llama-server.

### 5. Autostart via systemd --user

```bash
bash scripts/linux/install-autostart.sh
```

Status/Logs:

```bash
systemctl --user status turboquant-gateway.service
journalctl --user -u turboquant-gateway.service -f
```

Der Service startet standardmäßig beim User-Login. Optionaler Start bereits ohne Login:

```bash
sudo loginctl enable-linger "$USER"
```

## Hermes

Hermes verwendet auf Windows und Linux denselben benannten Custom Provider `turboquant` mit `http://127.0.0.1:9292/v1`. Die per-model Context-Längen werden explizit mit 200K bzw. 250K hinterlegt.

In einer laufenden Session z. B.:

```text
/model custom:turboquant:qwen3.8-27b-200k
/model custom:turboquant:qwen3.8-27b-250k
/model custom:turboquant:qwen3.8-27b-200k-mtp
```

Die vollständige `~/.hermes/config.yaml`-Ergänzung steht in [docs/HERMES.md](docs/HERMES.md).

## OpenCode

OpenCode bekommt denselben OpenAI-kompatiblen Provider:

```text
baseURL = http://127.0.0.1:9292/v1
```

Die Model-Auswahl kommt aus `/v1/models`; ein Wechsel des Model-IDs triggert automatisch den passenden llama-server.

## Direkter llama-server Start

Nur für Debugging/Benchmarks:

```powershell
.\scripts\windows\start-server.ps1 27b-200k
```

```bash
bash scripts/linux/start-server.sh 27b-200k
```

Im normalen Betrieb läuft nur der Gateway.

## Engine

Aktuell: `TheTom/llama-cpp-turboquant`, Branch `feature/turboquant-kv-cache`. Die Engine unterstützt `turbo2`, `turbo3` und `turbo4` als Runtime-KV-Cache-Formate sowie aktuelle Qwen-MTP-Pfade.

Siehe auch [docs/SETUP.md](docs/SETUP.md).
