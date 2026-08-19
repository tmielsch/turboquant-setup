#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-}"
shift || true
CONTEXT=""
KV_PRESET="default"
MTP=0

while (($#)); do
  case "$1" in
    --context) CONTEXT="$2"; shift 2 ;;
    --kv-preset) KV_PRESET="$2"; shift 2 ;;
    --mtp) MTP=1; shift ;;
    *) echo "Unbekannter Parameter: $1" >&2; exit 2 ;;
  esac
done

case "$PROFILE" in
  9b|27b|27b-200k|27b-250k) ;;
  *) echo "Usage: bash scripts/linux/start-server.sh {9b|27b|27b-200k|27b-250k} [--context N] [--kv-preset default|balanced|max] [--mtp]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/common/profiles.conf"

SERVER="$ROOT/$BUILD_DIR/bin/llama-server"
[[ -x "$SERVER" ]] || { echo "llama-server fehlt. Erst bash scripts/linux/setup.sh ausführen." >&2; exit 1; }

if [[ "$PROFILE" == 27b* ]]; then
  MODEL="$ROOT/$MODEL_27B"
  if [[ -n "$CONTEXT" ]]; then
    CTX="$CONTEXT"
  elif [[ "$PROFILE" == "27b-250k" ]]; then
    CTX="$CTX_27B_MAX"
  else
    CTX="$CTX_27B"
  fi
  case "$KV_PRESET" in
    balanced) KV_K=q8_0; KV_V=turbo3 ;;
    max|default) KV_K="$KV_K_27B"; KV_V="$KV_V_27B" ;;
    *) echo "Ungültiges KV-Preset: $KV_PRESET" >&2; exit 2 ;;
  esac
else
  MODEL="$ROOT/$MODEL_9B"
  CTX="${CONTEXT:-$CTX_9B}"
  KV_K="$KV_K_9B"
  KV_V="$KV_V_9B"
fi

[[ -f "$MODEL" ]] || { echo "Modell fehlt: $MODEL" >&2; exit 1; }

ARGS=(
  -m "$MODEL"
  -fit "$FIT"
  -fitt "$FIT_TARGET_MIB"
  -c "$CTX"
  -ctk "$KV_K"
  -ctv "$KV_V"
  --flash-attn on
  --jinja
  -np 1
  --host "$HOST"
  --port "$PORT"
)

if [[ "$PROFILE" == 27b* && "$MTP" -eq 1 ]]; then
  DRAFT="$ROOT/$MTP_DRAFT_27B"
  [[ -f "$DRAFT" ]] || { echo "MTP-Draft fehlt: $DRAFT" >&2; exit 1; }
  ARGS+=(
    --spec-type draft-mtp
    --spec-draft-model "$DRAFT"
    --spec-draft-n-max "$MTP_DRAFT_N_MAX"
    --spec-chain "$MTP_CHAIN"
  )
fi

echo "Starte llama-server"
echo "  Profil:   $PROFILE"
echo "  Context:  $CTX"
echo "  KV:       K=$KV_K / V=$KV_V"
echo "  MTP:      $MTP"
echo "  VRAM fit: auto (target margin $FIT_TARGET_MIB MiB)"

exec "$SERVER" "${ARGS[@]}"
