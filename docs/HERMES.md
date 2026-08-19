# Hermes + TurboQuant Gateway

Hermes spricht mit dem dauerhaft laufenden `llama-swap` Gateway unter:

```text
http://127.0.0.1:9292/v1
```

`llama-swap` veröffentlicht die virtuellen Qwen-Varianten über `/v1/models` und lädt die zugehörige llama.cpp-Konfiguration erst beim ersten Request.

## Empfohlene Hermes-Konfiguration

Für zuverlässige Context-Grenzen die Varianten als benannten Custom Provider in `~/.hermes/config.yaml` hinterlegen:

```yaml
custom_providers:
  - name: turboquant
    base_url: http://127.0.0.1:9292/v1
    models:
      qwen3.5-9b-32k:
        context_length: 32768
      qwen3.8-27b-64k:
        context_length: 65536
      qwen3.8-27b-128k:
        context_length: 131072
      qwen3.8-27b-200k:
        context_length: 200000
      qwen3.8-27b-250k:
        context_length: 250000
```

Kein globales `model.context_length` setzen, weil dieser Wert die per-model Context-Längen überschreiben würde.

## Wechsel in einer laufenden Hermes-Session

```text
/model custom:turboquant:qwen3.8-27b-64k
/model custom:turboquant:qwen3.8-27b-128k
/model custom:turboquant:qwen3.8-27b-200k
/model custom:turboquant:qwen3.8-27b-250k
```

Beim Wechsel sendet Hermes den ausgewählten Model-ID an `llama-swap`. Falls eine andere Variante läuft, wird sie beendet und die neue llama-server-Commandline gestartet. Die 27B-GGUF selbst liegt nur einmal im `models/`-Ordner.

## Ersteinrichtung über Hermes

Alternativ zunächst:

```text
hermes model
→ Custom endpoint
→ http://127.0.0.1:9292/v1
```

Der Gateway stellt `/v1/models` bereit. Für die dauerhafte Nutzung mehrerer Varianten ist die obige `custom_providers`-Konfiguration trotzdem vorzuziehen, weil damit die jeweilige Context-Länge eindeutig feststeht.
