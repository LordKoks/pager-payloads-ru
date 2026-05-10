#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Оповещение Handshake
# Author: NullSec
# Description: Отслеживает захваты WPA handshake и уведомляет с информацией SSID/BSSID
# Category: nullsec/alerts

LOOT_DIR="/mmc/nullsec/handshakealert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ HANDSHAKE

Мониторит каталоги захвата
на новые файлы WPA handshake
и уведомляет при обнаружении.

Возможности:
- слежение за .cap/.pcap
- извлечение SSID/BSSID
- проверка handshake
- уведомления в реальном времени

Нажмите OK для настройки."

PROMPT "ДИРЕКТОРИЯ ДЛЯ ОТСЛЕЖИВАНИЯ:

1. /mmc/nullsec/handshakes
2. /mmc/nullsec/captures
3. /tmp/captures

Выберите директорию далее."

DIR_SEL=$(NUMBER_PICKER "Директория (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DIR_SEL=1 ;; esac

case $DIR_SEL in
    1) WATCH_DIR="/mmc/nullsec/handshakes" ;;
    2) WATCH_DIR="/mmc/nullsec/captures" ;;
    3) WATCH_DIR="/tmp/captures" ;;
    *) WATCH_DIR="/mmc/nullsec/handshakes" ;;
esac

mkdir -p "$WATCH_DIR"

if ! command -v aircrack-ng >/dev/null 2>&1; then
    ERROR_DIALOG "aircrack-ng не найден!

Требуется для проверки
handshake."
    exit 1
fi

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

VALIDATE=$(CONFIRMATION_DIALOG "Проверять handshake?

Запустить aircrack-ng для проверки
каждого захвата на наличие
валидного WPA handshake.")
[ "$VALIDATE" = "$DUCKYSCRIPT_USER_CONFIRMED" ] && DO_VALIDATE=1 || DO_VALIDATE=0

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ СЛЕЖЕНИЕ?

Директория: $WATCH_DIR
Длительность: ${DURATION} мин
Проверка: $([ $DO_VALIDATE -eq 1 ] && echo YES || echo NO)

Нажмите OK, чтобы начать.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/hsalert_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ HANDSHAKE ===" > "$LOG_FILE"
echo "Начато: $(date)" >> "$LOG_FILE"
echo "Каталог: $WATCH_DIR" >> "$LOG_FILE"
echo "===========================" >> "$LOG_FILE"

# Снимок существующих файлов
ls "$WATCH_DIR"/*.cap "$WATCH_DIR"/*.pcap 2>/dev/null | sort > /tmp/hs_known.txt

END_TIME=$(($(date +%s) + DURATION * 60))
HS_COUNT=0

LOG "Слежение за $WATCH_DIR на наличие handshake..."
SPINNER_START "Ожидание захватов..."

while [ $(date +%s) -lt $END_TIME ]; do
    # Проверка новых файлов захвата
    ls "$WATCH_DIR"/*.cap "$WATCH_DIR"/*.pcap 2>/dev/null | sort > /tmp/hs_current.txt
    NEW_FILES=$(comm -13 /tmp/hs_known.txt /tmp/hs_current.txt 2>/dev/null)

    if [ -n "$NEW_FILES" ]; then
        while IFS= read -r CAPFILE; do
            [ -z "$CAPFILE" ] && continue
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            FNAME=$(basename "$CAPFILE")
            VALID="не проверено"

            # Извлечение SSID/BSSID
            SSID_INFO=$(aircrack-ng "$CAPFILE" 2>/dev/null | grep -E "^\s+[0-9]+" | head -1)
            BSSID=$(echo "$SSID_INFO" | awk '{print $2}')
            ESSID=$(echo "$SSID_INFO" | awk '{for(i=5;i<=NF;i++) printf $i" "; print ""}' | sed 's/[[:space:]]*$//')
            [ -z "$BSSID" ] && BSSID="unknown"
            [ -z "$ESSID" ] && ESSID="unknown"

            # Проверка handshake, если включено
            if [ $DO_VALIDATE -eq 1 ]; then
                if aircrack-ng "$CAPFILE" 2>/dev/null | grep -q "1 handshake"; then
                    VALID="VALID"
                else
                    VALID="нет handshake"
                fi
            fi

            HS_COUNT=$((HS_COUNT + 1))
            echo "[$TIMESTAMP] $FNAME SSID:$ESSID BSSID:$BSSID [$VALID]" >> "$LOG_FILE"
            LOG "Обнаружен handshake: $ESSID"

            SPINNER_STOP
            PROMPT "⚠ ОБНАРУЖЕН HANDSHAKE!

Файл: $FNAME
SSID: $ESSID
BSSID: $BSSID
Статус: $VALID
Время: $TIMESTAMP

Всего захватов: $HS_COUNT

Нажмите OK, чтобы продолжить."
            SPINNER_START "Слежение..."
        done <<< "$NEW_FILES"

        cp /tmp/hs_current.txt /tmp/hs_known.txt
    fi

    sleep 5
done

SPINNER_STOP
rm -f /tmp/hs_known.txt /tmp/hs_current.txt

echo "===========================" >> "$LOG_FILE"
echo "Окончено: $(date)" >> "$LOG_FILE"
echo "Найдено handshake: $HS_COUNT" >> "$LOG_FILE"

PROMPT "СЛЕЖЕНИЕ ЗАВЕРШЕНО

Длительность: ${DURATION} мин
Найдено handshake: $HS_COUNT

Журнал сохранен в:
$LOG_FILE

Нажмите OK для выхода."
