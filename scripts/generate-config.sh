#!/usr/bin/env bash
# Generate llama-swap/config.yaml from models.conf.
#
# Usage: bash scripts/generate-config.sh
#
# The output file is bind-mounted into the turboquant container, so no
# Docker image rebuild is needed. Apply with:
#   docker compose restart turboquant

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/models.conf"
OUT="$ROOT/llama-swap/config.yaml"

if [[ ! -f "$CONF" ]]; then
    echo "error: $CONF not found" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- split models.conf into per-section files --------------------------------
awk '
    /^[[:space:]]*#/ { next }
    /^\[/ {
        section = $0
        gsub(/^\[/, "", section)
        gsub(/\]$/, "", section)
        sub(/^[[:space:]]*/, "", section)
        sub(/[[:space:]]*$/, "", section)
        file = "'"$TMP"'/" section ".conf"
        next
    }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
        if (file != "") print >> file
    }
' "$CONF"

# --- helper: read a section file into a temp file for sourcing ---------------
read_section() { # $1 = path, writes normalized key=value pairs to stdout
    local f="$1"
    [[ -f "$f" ]] || return 1
    sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$/\1=\2/' "$f"
}

# --- YAML string quoting -----------------------------------------------------
yq_str() { # $1 = raw string, prints double-quoted YAML string
    local s="${1//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# --- globals -----------------------------------------------------------------
declare -A G
while IFS='=' read -r k v; do
    [[ -n "$k" && -n "$v" ]] && G["$k"]="$v"
done < <(read_section "$TMP/global.conf")

ENGINE="${G[engine]:-/app/llama-server}"
FIT_TARGET="${G[fit_target]:-512}"
KV_K_DEF="${G[kv_k]:-q8_0}"
KV_V_DEF="${G[kv_v]:-turbo2}"

# --- models ------------------------------------------------------------------
MODEL_SECTIONS=()
for f in "$TMP"/model*.conf; do
    [[ -f "$f" ]] || continue
    MODEL_SECTIONS+=("$f")
done

if [[ ${#MODEL_SECTIONS[@]} -eq 0 ]]; then
    echo "error: no [model:*] sections found in $CONF" >&2
    exit 1
fi

# --- emit config.yaml ---------------------------------------------------------
{
    cat <<EOF
# AUTO-GENERATED from models.conf by scripts/generate-config.sh.
# Do not edit by hand - your changes will be overwritten.
# Regenerate with:  bash scripts/generate-config.sh
# Apply with:       docker compose restart turboquant

startPort: 5800
sendLoadingState: false
globalTTL: 0

macros:
  engine: $(yq_str "$ENGINE")
  fit_target: $(yq_str "$FIT_TARGET")

models:
EOF

    for f in "${MODEL_SECTIONS[@]}"; do
        declare -A M=()
        while IFS='=' read -r k v; do
            [[ -n "$k" && -n "$v" ]] && M["$k"]="$v"
        done < <(read_section "$f")

        local_id="${M[id]:-}"
        if [[ -z "$local_id" ]]; then
            local_id="$(basename "$f")"
            local_id="${local_id#model:}"
            local_id="${local_id%.conf}"
        fi
        local_file="${M[file]:-}"
        local_ctx="${M[context]:-}"
        if [[ -z "$local_id" || -z "$local_file" || -z "$local_ctx" ]]; then
            echo "error: section in $f is missing id, file or context" >&2
            exit 1
        fi

        local_name="${M[name]:-$local_id}"
        local_desc="${M[description]:-}"
        local_kvk="${M[kv_k]:-$KV_K_DEF}"
        local_kvv="${M[kv_v]:-$KV_V_DEF}"
        local_mtp="${M[mtp_draft]:-}"
        local_tools="${M[tools]:-true}"

        printf '  %s:\n' "$(yq_str "$local_id")"
        printf '    name: %s\n' "$(yq_str "$local_name")"
        if [[ -n "$local_desc" ]]; then
            printf '    description: %s\n' "$(yq_str "$local_desc")"
        fi
        cat <<EOF
    cmd: |
      "\${engine}" --host 127.0.0.1 --port \${PORT}
      --alias \${MODEL_ID}
      -m $(yq_str "/models/$local_file")
      -fit on -fitt \${fit_target}
      -c $local_ctx
      -ctk $local_kvk -ctv $local_kvv
      --flash-attn on --jinja -np 1
EOF
        if [[ -n "$local_mtp" ]]; then
            cat <<EOF
      --spec-type draft-mtp
      --spec-draft-model $(yq_str "/models/$local_mtp")
      --spec-draft-n-max 3
      --spec-chain 8
EOF
        fi
        cat <<EOF
    capabilities:
      in: [text]
      out: [text]
      tools: $local_tools
      context: $local_ctx
EOF
        unset M
    done
} > "$OUT"

echo "generated $OUT ($(grep -c '^  "' "$OUT") model profiles)"
