#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/scripts/linux/start-gateway.sh"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/turboquant-gateway.service"

[[ -f "$LAUNCHER" ]] || { echo "Gateway-Launcher fehlt: $LAUNCHER" >&2; exit 1; }
mkdir -p "$UNIT_DIR"

cat > "$UNIT" <<EOF
[Unit]
Description=TurboQuant llama-swap gateway
After=graphical-session.target network.target

[Service]
Type=simple
ExecStart=/usr/bin/bash "$LAUNCHER"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now turboquant-gateway.service

echo "Autostart eingerichtet: $UNIT"
echo "Status: systemctl --user status turboquant-gateway.service"
echo "Logs:   journalctl --user -u turboquant-gateway.service -f"
echo
echo "Der User-Service startet normalerweise beim Login. Für Start schon vor dem Login optional:"
echo "  sudo loginctl enable-linger $USER"
