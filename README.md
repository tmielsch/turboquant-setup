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

Alle vier 27B-Varianten referenzieren **dieselbe** `Qwen3.8-27B-UD-Q3_K_XL.gguf`. Es werden keine Modellkopien angelegt.

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

Danach:

- API: `http://127.0.0.1:9292/v1`
- Model Discovery: `http://127.0.0.1:9292/v1/models`
- Web UI: `http://127.0.0.1:9292/ui`

Beim Gateway-Start wird **kein Modell geladen**. Erst ein Request mit z. B. `model: qwen3.8-27b-250k` startet den dazugehörigen llama-server.

### 4. Optional: Autostart beim Windows-Login

```powershell
.\scripts\windows\install-autostart.ps1
```

Damit läuft nur der kleine llama-swap Gateway nach dem Login. Das 27B-Modell belegt erst VRAM, wenn Hermes/OpenCode es tatsächlich anfordert.

## Hermes

Einmalig:

```text
hermes model
→ Custom endpoint
→ Base URL: http://127.0.0.1:9292/v1
```

Der Endpoint stellt `/v1/models` bereit, sodass Hermes die virtuellen Modelle entdecken kann. Danach kann innerhalb von Hermes z. B. gewechselt werden:

```text
/model custom:qwen3.8-27b-200k
/model custom:qwen3.8-27b-250k
/model custom:qwen3.8-27b-200k-mtp
```

Die Context-Länge ist außerdem als Capability der jeweiligen llama-swap Model-ID hinterlegt (200000 bzw. 250000).

## OpenCode

OpenCode bekommt denselben OpenAI-kompatiblen Provider:

```text
baseURL = http://127.0.0.1:9292/v1
```

Die Model-Auswahl kommt aus `/v1/models`; ein Wechsel des Model-IDs triggert automatisch den passenden llama-server.

## Direkter llama-server Start

`scripts/windows/start-server.ps1` bleibt als Debug-/Benchmark-Werkzeug erhalten. Im normalen Betrieb sollte stattdessen `start-gateway.ps1` laufen.

## Engine

Aktuell: `TheTom/llama-cpp-turboquant`, Branch `feature/turboquant-kv-cache`. Die Engine unterstützt `turbo2`, `turbo3` und `turbo4` als Runtime-KV-Cache-Formate sowie aktuelle Qwen-MTP-Pfade.

Siehe auch [docs/SETUP.md](docs/SETUP.md).
