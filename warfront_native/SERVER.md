# Свой сервер для «Боевого Фронта»

Сервер — это та же игра, запущенная без графики. Он только пересылает сообщения между игроками,
поэтому хватает самого дешёвого VPS: 1 ядро, 1 ГБ памяти, Linux (Ubuntu 22.04/24.04). Такой сервер держит 10+ игроков.

## Где взять VPS

- Timeweb Cloud — https://timeweb.cloud/services/vds-vps (оплата картой РФ, от ~200–300 ₽/мес)
- Selectel — https://selectel.ru/services/cloud/servers/
- Aeza — https://aeza.net/ru/virtual-servers
- Бесплатно навсегда: Oracle Cloud Free Tier — https://www.oracle.com/cloud/free/ (ARM-сервер, нужна карта для регистрации;
  для него качайте сборку `BoevoyFront-Server-ARM.zip`)

## Установка одной командой (можно с телефона)

Откройте консоль сервера (в панели хостинга кнопка «Консоль», или приложение Termius на телефоне) и вставьте:

```bash
curl -sL https://raw.githubusercontent.com/pidor95/smoothaim/claude/military-vehicles-pvp-game-wm8y3e/warfront_native/server/install.sh | bash
```

В конце будет написан адрес сервера для игры.

## Установка вручную (5 минут)

Подключитесь к серверу по SSH (`ssh root@IP-сервера`) и выполните:

```bash
apt update && apt install -y unzip curl
mkdir -p /opt/boevoy && cd /opt/boevoy
curl -L -o server.zip https://github.com/pidor95/smoothaim/releases/download/boevoy-front-native/BoevoyFront-Server-Linux.zip
unzip -o server.zip && chmod +x BoevoyFront-Server.x86_64
# открыть порты (если включён ufw)
ufw allow 27015:27016/udp || true
# автозапуск
cat > /etc/systemd/system/boevoy.service <<'UNIT'
[Unit]
Description=Boevoy Front server
After=network.target
[Service]
WorkingDirectory=/opt/boevoy
ExecStart=/opt/boevoy/BoevoyFront-Server.x86_64 --headless -- server name="Мой сервер" port=27015 max=10
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now boevoy
systemctl status boevoy --no-pager
```

Порты: 27015/UDP — игра, 27016/UDP — запрос статуса (название и число игроков).
У облачных провайдеров эти порты иногда надо открыть ещё и в панели управления («Файрвол» / «Security list»).

## Как игроки попадут на сервер

- Быстро: в игре «Онлайн» → «Добавить» → введите `IP-сервера:27015`.
- Для всех сразу: впишите сервер в файл `warfront_native/servers.json` в репозитории — игра скачивает этот список при открытии вкладки «Онлайн»:

```json
{"servers": [{"name": "Мой сервер", "host": "185.10.20.30", "port": 27015}]}
```
