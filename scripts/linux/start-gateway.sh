#!/usr/bin/env bash
set -euo pipefail

LISTEN="${1:-127.0.0.1:9292}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/scripts/common/profiles.conf"

# shellcheck disable=SC1090
source "$CONF"

if ! command -v llama-swap >/dev/null 2>&1; then
  echo "llama-swap fehlt." >&2
  echo "Installiere das Linux-Binary aus den offiziellen Releases oder via Homebrew:" >&2
  echo "  brew tap mostlygeek/llama-swap && brew install llama-swap" >&2
  exit 1
fi

BUILD="$ROOT/$BUILD_DIR"
ENGINE="$BUILD/bin/llama-server"
MODEL_9B_ABS="$ROOT/$MODEL_9B"
MODEL_27B_ABS="$ROOT/$MODEL_27B"
MTP_27B_ABS="$ROOT/$MTP_DRAFT_27B"
CONFIG="$ROOT/llama-swap/config.yaml"

[[ -x "$ENGINE" ]] || { echo "TurboQuant llama-server fehlt: $ENGINE" >&2; echo "Erst: bash scripts/linux/setup.sh" >&2; exit 1; }
[[ -f "$MODEL_27B_ABS" ]] || { echo "27B-Modell fehlt: $MODEL_27B_ABS" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "llama-swap config fehlt: $CONFIG" >&2; exit 1; }

[[ -f "$MODEL_9B_ABS" ]] || echo "Warnung: 9B-Modell fehlt; qwen3.5-9b-32k kann nicht geladen werden." >&2
[[ -f "$MTP_27B_ABS" ]] || echo "Warnung: MTP-Draft fehlt; *-mtp Varianten können nicht geladen werden." >&2

export TQ_ENGINE="$ENGINE"
export TQ_MODEL_27B="$MODEL_27B_ABS"
export TQ_MODEL_9B="$MODEL_9B_ABS"
export TQ_MTP_DRAFT_27B="$MTP_27B_ABS"

echo "TurboQuant Gateway"
echo "  API:      http://$LISTEN/v1"
echo "  Web UI:   http://$LISTEN/ui"
echo "  Engine:   $ENGINE"
echo "  Models:   qwen3.8-27b-200k, qwen3.8-27b-250k, *-mtp"
echo
echo "Kein Modell wird beim Start geladen. llama-swap startet die angeforderte Variante on demand."

exec llama-swap --config "$CONFIG" --listen "$LISTEN" --watch-config
