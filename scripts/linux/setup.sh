#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/scripts/common/profiles.conf"

if [[ ! -f "$CONF" ]]; then
  echo "profiles.conf fehlt: $CONF" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONF"

missing=()
for cmd in git cmake nvcc; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if ((${#missing[@]})); then
  echo "Fehlende Build-Werkzeuge: ${missing[*]}" >&2
  echo "Auf CachyOS/Arch typischerweise:" >&2
  echo "  sudo pacman -S --needed base-devel git cmake cuda" >&2
  exit 1
fi

ENGINE="$ROOT/$ENGINE_DIR"
BUILD="$ROOT/$BUILD_DIR"

mkdir -p "$(dirname "$ENGINE")" "$BUILD"

if [[ ! -d "$ENGINE/.git" ]]; then
  git clone --branch "$FORK_BRANCH" "$FORK_URL" "$ENGINE"
else
  echo "Engine vorhanden; aktualisiere $FORK_BRANCH ..."
  git -C "$ENGINE" fetch origin "$FORK_BRANCH"
  git -C "$ENGINE" checkout "$FORK_BRANCH"
  git -C "$ENGINE" pull --ff-only origin "$FORK_BRANCH"
fi

cmake -S "$ENGINE" -B "$BUILD" \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=89 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD" -j"$(nproc)" --target llama-server llama-cli llama-bench

SERVER="$BUILD/bin/llama-server"
if [[ ! -x "$SERVER" ]]; then
  echo "llama-server nicht gefunden: $SERVER" >&2
  exit 1
fi

echo
echo "Engine: $FORK_URL @ $FORK_BRANCH"
"$SERVER" --version
echo "OK: TurboQuant-Setup abgeschlossen. Server: $SERVER"
