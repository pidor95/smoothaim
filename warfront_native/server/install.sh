#!/bin/bash
# One-command install of the Boevoy Front dedicated server on Ubuntu/Debian:
#   curl -sL https://raw.githubusercontent.com/pidor95/smoothaim/claude/military-vehicles-pvp-game-wm8y3e/warfront_native/server/install.sh | bash
set -e
NAME="${1:-Боевой Фронт}"
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then ZIP=BoevoyFront-Server-ARM.zip; BIN=BoevoyFront-Server.arm64; else ZIP=BoevoyFront-Server-Linux.zip; BIN=BoevoyFront-Server.x86_64; fi
apt-get update -qq && apt-get install -y -qq unzip curl >/dev/null
mkdir -p /opt/boevoy && cd /opt/boevoy
curl -sL -o server.zip "https://github.com/pidor95/smoothaim/releases/download/boevoy-front-native/$ZIP"
unzip -o -q server.zip && chmod +x "$BIN"
command -v ufw >/dev/null && ufw allow 27015:27016/udp >/dev/null || true
cat > /etc/systemd/system/boevoy.service <<UNIT
[Unit]
Description=Boevoy Front server
After=network.target
[Service]
WorkingDirectory=/opt/boevoy
ExecStart=/opt/boevoy/$BIN --headless -- server name="$NAME" port=27015 max=10
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable boevoy >/dev/null 2>&1
systemctl restart boevoy
sleep 3
IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
if systemctl is-active --quiet boevoy; then
  echo ""
  echo "=== СЕРВЕР ЗАПУЩЕН ==="
  echo "Адрес для игры: $IP:27015"
  echo "В игре: Онлайн -> Добавить -> $IP:27015"
else
  echo "Сервер не запустился, лог:"; journalctl -u boevoy -n 20 --no-pager
fi
