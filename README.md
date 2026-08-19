# TurboQuant Setup

Lokales llama.cpp/TurboQuant-Setup für sehr lange Kontexte auf begrenztem VRAM.

## Zielhardware / Hauptprofil

- RTX 4070 Ti SUPER 16 GB
- Qwen3.8-27B `UD-Q3_K_XL`
- 200K Context als Standard, 250K als zweites Profil
- asymmetrischer TurboQuant-KV-Cache: `q8_0` für K, `turbo2` für V
- automatisches VRAM-Fitting: Kontext bleibt fest, GPU-Offload wird passend gewählt
- optional Qwen3.8 MTP

## Windows

Engine bauen/aktualisieren:

```powershell
.\scripts\windows\setup.ps1
```

200K, aggressive Long-Context-Konfiguration:

```powershell
.\scripts\windows\start-server.ps1 27b-200k
```

250K:

```powershell
.\scripts\windows\start-server.ps1 27b-250k
```

Beliebige Kontextlänge bis 262144 Tokens:

```powershell
.\scripts\windows\start-server.ps1 27b -Context 225000
```

Konservativer KV-Cache (`q8_0/turbo3`):

```powershell
.\scripts\windows\start-server.ps1 27b-200k -KvPreset balanced
```

MTP zusätzlich aktivieren:

```powershell
.\scripts\windows\start-server.ps1 27b-200k -Mtp
```

MTP ist bewusst optional: der Draft-Head braucht selbst VRAM und kann bei 16 GB den optimalen Weight-Offload verändern. Erst Baseline ohne MTP messen, dann mit MTP vergleichen.

## Engine

Verwendet wird aktuell `TheTom/llama-cpp-turboquant`, Branch `feature/turboquant-kv-cache`. Die Engine unterstützt `turbo2`, `turbo3` und `turbo4` als Runtime-KV-Cache-Formate sowie aktuelle Qwen-MTP-Pfade.

Siehe auch [docs/SETUP.md](docs/SETUP.md).
