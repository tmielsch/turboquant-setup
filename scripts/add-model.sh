#!/usr/bin/env bash
# Interactive wizard for adding a new model to turboquant-setup.
#
# Usage: bash scripts/add-model.sh
#
# Steps:
#   1. Ask for the GGUF file (local path or download URL)
#   2. Ask for model ID, name, context size, optional MTP draft
#   3. Appends a [model:<id>] section to models.conf
#   4. Regenerates llama-swap/config.yaml (scripts/generate-config.sh)
#   5. Optionally restarts the turboquant container (no image rebuild!)
#
# The GGUF must fit into your GPU VRAM together with the KV cache:
# rule of thumb - 16 GB GPU handles a ~13 GB model at 200K context with
# TurboQuant KV cache (q8_0 K + turbo2 V).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/models.conf"
GEN="$ROOT/scripts/generate-config.sh"

# --- resolve MODELS_DIR from .env (or default to ./models) -------------------
MODELS_DIR="$ROOT/models"
if [[ -f "$ROOT/.env" ]]; then
    ENV_MODELS="$(sed -nE 's/^MODELS_DIR[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$ROOT/.env" | tail -1)"
    if [[ -n "$ENV_MODELS" ]]; then
        case "$ENV_MODELS" in
            /*) MODELS_DIR="$ENV_MODELS" ;;
            *)  MODELS_DIR="$ROOT/$ENV_MODELS" ;;
        esac
    fi
fi

prompt() { # $1 = prompt text, $2 = default (may be empty)
    local p="$1" def="$2"
    if [[ -n "$def" ]]; then
        read -r -p "$p [$def]: " ans
        echo "${ans:-$def}"
    else
        read -r -p "$p: " ans
        echo "$ans"
    fi
}

confirm() { # $1 = question -> 0/1
    local ans
    read -r -p "$1 [y/N]: " ans
    [[ "$ans" =~ ^[yYjJ]$ ]]
}

valid_id() { # $1 = id -> 0/1 (lowercase letters, digits, dots, dashes, underscores)
    [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

echo "== TurboQuant: add model =="
echo "Models directory: $MODELS_DIR"
echo

# --- GGUF source --------------------------------------------------------------
while true; do
    src="$(prompt "GGUF file (local path) or download URL" "")"
    [[ -n "$src" ]] && break
    echo "Please enter something."
done

if [[ "$src" =~ ^https?:// ]]; then
    filename="$(basename "${src%%\?*}")"
    filename="$(prompt "Filename in $MODELS_DIR" "$filename")"
    dest="$MODELS_DIR/$filename"
    if [[ -e "$dest" ]] && ! confirm "File $dest already exists - overwrite?"; then
        echo "Aborted."
        exit 1
    fi
    echo "Downloading $src ..."
    curl -L --fail --retry 5 -C - -o "$dest" "$src"
    echo "Downloaded: $dest ($(du -h "$dest" | cut -f1))"
else
    if [[ ! -f "$src" ]]; then
        echo "error: $src does not exist" >&2
        exit 1
    fi
    filename="$(basename "$src")"
    mkdir -p "$MODELS_DIR"
    if [[ -e "$MODELS_DIR/$filename" ]]; then
        echo "Note: $MODELS_DIR/$filename already exists, keeping existing file."
    else
        cp "$src" "$MODELS_DIR/$filename"
        echo "Copied to $MODELS_DIR/$filename"
    fi
fi

# --- model metadata -----------------------------------------------------------
while true; do
    id="$(prompt "Model ID (used in API requests, e.g. mymodel-32k)" "")"
    if [[ -z "$id" ]]; then
        echo "Model ID is required."
    elif ! valid_id "$id"; then
        echo "Invalid ID: use lowercase letters, digits, '.', '-', '_'."
    elif grep -q "^\[model:$id\]" "$CONF"; then
        echo "Model ID '$id' already exists in models.conf."
    else
        break
    fi
done

name="$(prompt "Display name" "$(basename "$filename" .gguf)")"
description="$(prompt "Description (optional)" "")"
context="$(prompt "Context size in tokens (e.g. 32768, 131072)" "32768")"
case "$context" in
    ''|*[!0-9]*) echo "error: context size must be a number" >&2; exit 1 ;;
esac

echo
echo "KV cache (see docs/MODELS.md for options):"
kv_k="$(prompt "K cache quantization" "q8_0")"
kv_v="$(prompt "V cache quantization" "turbo2")"

mtp_draft=""
if confirm "Add an MTP speculative-decoding draft model?"; then
    mtp_src="$(prompt "MTP draft GGUF (local path or URL)" "")"
    if [[ "$mtp_src" =~ ^https?:// ]]; then
        mtp_filename="$(basename "${mtp_src%%\?*}")"
        curl -L --fail --retry 5 -C - -o "$MODELS_DIR/$mtp_filename" "$mtp_src"
        echo "Downloaded draft: $MODELS_DIR/$mtp_filename"
        mtp_draft="$mtp_filename"
    else
        if [[ ! -f "$mtp_src" ]]; then
            echo "error: $mtp_src does not exist" >&2
            exit 1
        fi
        mtp_draft="$(basename "$mtp_src")"
        cp -n "$mtp_src" "$MODELS_DIR/$mtp_draft" || true
        echo "Copied draft to $MODELS_DIR/$mtp_draft"
    fi
fi

# --- write to models.conf ------------------------------------------------------
{
    echo
    echo "[model:$id]"
    echo "name=$name"
    [[ -n "$description" ]] && echo "description=$description"
    echo "file=$filename"
    echo "context=$context"
    echo "kv_k=$kv_k"
    echo "kv_v=$kv_v"
    [[ -n "$mtp_draft" ]] && echo "mtp_draft=$mtp_draft"
} >> "$CONF"

# --- optional container restart ------------------------------------------------
if confirm "Restart the turboquant container now?"; then
    if (cd "$ROOT" && docker compose restart turboquant); then
        echo
        echo "Available model IDs:"
        curl -s http://127.0.0.1:9292/v1/models | python3 -c "import json,sys; [print(' -', m['id']) for m in json.load(sys.stdin)['data']]" 2>/dev/null \
            || echo "(gateway not reachable yet - check: curl http://127.0.0.1:9292/v1/models)"
    else
        echo
        echo "Container restart failed. Common causes:"
        echo " - your user is not in the docker group (fix: sudo usermod -aG docker \$USER, then re-login)"
        echo " - docker daemon not running (fix: sudo systemctl start docker)"
        echo "Once fixed: cd $ROOT && docker compose restart turboquant"
    fi
fi

echo
echo "Done. First request to '$id' loads the model into VRAM (~10-30 s)."
