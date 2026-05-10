#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: NullSec RickRoll AP
# Author: bad-antics
# Description: Создает открытую AP, которая перенаправляет всех на Rick Roll
# Category: nullsec

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "NULLSEC RICKROLL AP

Создает открытую WiFi сеть,
которая перенаправляет ВСЕ трафик на
Rick Astley 'Never Gonna
Give You Up'!

Нажмите ОК для настройки."

SSID=$(TEXT_PICKER "Имя AP:" "Free Public WiFi")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SSID="Free Public WiFi" ;; esac

DURATION=$(NUMBER_PICKER "Длительность (секунды):" 600)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=600 ;; esac

resp=$(CONFIRMATION_DIALOG "Запустить RickRoll AP?

SSID: $SSID
Длительность: ${DURATION}s

Каждый кто подключится
получит RICK ROLL!")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

killall hostapd dnsmasq lighttpd 2>/dev/null

# Setup AP
cat > /tmp/rickroll_hostapd.conf << EOF
interface=$IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
auth_algs=1
wpa=0
EOF

hostapd /tmp/rickroll_hostapd.conf &
sleep 2

ifconfig $IFACE 10.0.0.1 netmask 255.255.255.0 up

# DNS redirect all to us
cat > /tmp/rickroll_dnsmasq.conf << EOF
interface=$IFACE
dhcp-range=10.0.0.10,10.0.0.100,12h
address=/#/10.0.0.1
EOF

dnsmasq -C /tmp/rickroll_dnsmasq.conf &

# RickRoll page
mkdir -p /tmp/rickroll
cat > /tmp/rickroll/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
<title>Connecting...</title>
<meta http-equiv="refresh" content="0; url=https://www.youtube.com/watch?v=dQw4w9WgXcQ">
<style>
body { background: #000; color: #0f0; font-family: monospace; text-align: center; padding-top: 100px; }
h1 { font-size: 48px; }
</style>
</head>
<body>
<h1>NULLSEC</h1>
<p>You've been rickrolled!</p>
<p>Redirecting...</p>
<script>window.location.href='https://www.youtube.com/watch?v=dQw4w9WgXcQ';</script>
</body>
</html>
HTML

# Simple HTTP server
cd /tmp/rickroll
if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server 80 &
elif command -v python >/dev/null 2>&1; then
    python -m SimpleHTTPServer 80 &
fi

LOG "RickRoll AP активен: $SSID"
sleep $DURATION

killall hostapd dnsmasq python python3 2>/dev/null

PROMPT "RICKROLL ЗАВЕРШЕН

SSID: $SSID
Длительность: ${DURATION}s

Надеюсь, кто-нибудь получил rick roll!

Нажмите ОК для выхода."
