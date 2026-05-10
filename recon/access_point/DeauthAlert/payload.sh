#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Deauth Alert
# Author: NullSec
# Description: Monitor for deauthentication frames and alert the user
# Category: nullsec/alerts

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# FIX: Check for tcpdump
if ! command -v tcpdump >/dev/null 2>&1; then
    ERROR_DIALOG "tcpdump не установлен!
Установите: opkg update && opkg install tcpdump"
    exit 1
fi

LOOT_DIR="/mmc/nullsec/deauthalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О ДЕАУТ

Отслеживает эфир на наличие
кадров деаутентификации и
сообщает о возможных атаках
в режиме реального времени.

Возможности:
- обнаружение деаутов
- запись MAC-адресов источников
- информация о канале и времени
- настраиваемая чувствительность

Нажмите OK, чтобы настроить."

# Detect monitor interface
MON_IF=""
for iface in wlan1mon wlan2mon wlan0mon; do
    [ -d "/sys/class/net/$iface" ] && MON_IF="$iface" && break
done
[ -z "$MON_IF" ] && { ERROR_DIALOG "Интерфейс мониторинга не найден!

Запустите: airmon-ng start wlan1"; exit 1; }

LOG "Интерфейс мониторинга: $MON_IF"

PROMPT "ЧУВСТВИТЕЛЬНОСТЬ:

1. Низкая (10+ деаутов/мин)
2. Средняя (5+ деаутов/мин)
3. Высокая (1+ деаут/мин)

Далее выберите порог."

SENSITIVITY=$(NUMBER_PICKER "Чувствительность (1-3):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SENSITIVITY=2 ;; esac
[ "$SENSITIVITY" -lt 1 ] && SENSITIVITY=1
[ "$SENSITIVITY" -gt 3 ] && SENSITIVITY=3

case $SENSITIVITY in
    1) THRESHOLD=10 ;;
    2) THRESHOLD=5 ;;
    3) THRESHOLD=1 ;;
esac

DURATION=$(NUMBER_PICKER "Monitor (minutes):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ МОНИТОРИНГ?

Интерфейс: $MON_IF
Порог: $THRESHOLD деаутов/мин
Длительность: ${DURATION} мин

Нажмите OK, чтобы начать.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/deauth_$(date +%Y%m%d_%H%M).log"
echo "=== DEAUTH ALERT LOG ===" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "Threshold: $THRESHOLD deauths/min" >> "$LOG_FILE"
echo "========================" >> "$LOG_FILE"

END_TIME=$(($(date +%s) + DURATION * 60))
TOTAL_DEAUTHS=0
ALERT_COUNT=0

LOG "Monitoring for deauth attacks..."
SPINNER_START "Scanning for deauth frames..."

while [ $(date +%s) -lt $END_TIME ]; do
    DEAUTH_COUNT=0

    for CH in 1 6 11 2 3 4 5 7 8 9 10; do
        [ $(date +%s) -ge $END_TIME ] && break
        iwconfig "$MON_IF" channel "$CH" 2>/dev/null

        # Capture deauth/disassoc frames (type 0 subtype 12 = deauth, subtype 10 = disassoc)
        HITS=$(timeout 2 tcpdump -i "$MON_IF" -c 100 -e 2>/dev/null | \
            grep -ci "deauthentication\|disassoc" 2>/dev/null || echo 0)
        DEAUTH_COUNT=$((DEAUTH_COUNT + HITS))

        if [ "$HITS" -gt 0 ]; then
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            # Extract source MACs from deauth frames
            SRC_MAC=$(timeout 1 tcpdump -i "$MON_IF" -c 5 -e 2>/dev/null | \
                grep -i "deauth" | awk '{print $2}' | head -1)
            [ -z "$SRC_MAC" ] && SRC_MAC="unknown"
            echo "[$TIMESTAMP] Ch:$CH Src:$SRC_MAC Count:$HITS" >> "$LOG_FILE"
        fi
    done

    TOTAL_DEAUTHS=$((TOTAL_DEAUTHS + DEAUTH_COUNT))

    if [ "$DEAUTH_COUNT" -ge "$THRESHOLD" ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        SPINNER_STOP
        LOG "ТРЕВОГА: обнаружено $DEAUTH_COUNT деаутов!"
        echo "[ALERT $(date '+%H:%M:%S')] $DEAUTH_COUNT deauths in sweep" >> "$LOG_FILE"

        PROMPT "⚠ ОБНАРУЖЕН ДЕАУТ!

$DEAUTH_COUNT кадров деаут
найдено за последний цикл.

Всего тревог: $ALERT_COUNT
Всего деаутов: $TOTAL_DEAUTHS

Нажмите OK, чтобы продолжить
мониторинг."
        SPINNER_START "Мониторинг..."
    fi

    sleep 1
done

SPINNER_STOP

echo "========================" >> "$LOG_FILE"
echo "Ended: $(date)" >> "$LOG_FILE"
echo "Total deauths: $TOTAL_DEAUTHS" >> "$LOG_FILE"
echo "Total alerts: $ALERT_COUNT" >> "$LOG_FILE"

PROMPT "МОНИТОРИНГ ЗАВЕРШЕН

Длительность: ${DURATION} мин
Всего деаутов: $TOTAL_DEAUTHS
Сработало тревог: $ALERT_COUNT

Лог сохранён в:
$LOG_FILE

Нажмите OK, чтобы выйти."
