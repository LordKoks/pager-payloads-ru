#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Название: Оповещение о рукопожатиях
# Автор: NullSec
# Описание: Отслеживание захватов рукопожатий WPA и оповещение с информацией об SSID/BSSID
# Категория: nullsec/alerts

LOOT_DIR="/mmc/nullsec/handshakealert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О РУКОПОЖАТИЯХ

Мониторинг каталогов захвата
на наличие новых файлов
рукопожатий WPA и оповещение
при их обнаружении.

Возможности:
- Отслеживание файлов .cap/.pcap
- Извлечение SSID/BSSID
- Проверка рукопожатий
- Уведомления в реальном времени

Нажмите ОК для настройки."

PROMPT "КАТАЛОГ НАБЛЮДЕНИЯ:

1. /mmc/nullsec/handshakes
2. /mmc/nullsec/captures
3. /tmp/captures

Выберите каталог далее."

DIR_SEL=$(NUMBER_PICKER "Каталог (1-3):" 1)
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
рукопожатий."
    exit 1
fi

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

VALIDATE=$(CONFIRMATION_DIALOG "Проверять рукопожатия?

Запустить aircrack-ng для
проверки наличия в каждом
захвате действительного
рукопожатия WPA.")
[ "$VALIDATE" = "$DUCKYSCRIPT_USER_CONFIRMED" ] && DO_VALIDATE=1 || DO_VALIDATE=0

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ НАБЛЮДЕНИЕ?

Каталог: $WATCH_DIR
Длительность: ${DURATION} мин
Проверка: $([ $DO_VALIDATE -eq 1 ] && echo ДА || echo НЕТ)

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/hsalert_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О РУКОПОЖАТИЯХ ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "Каталог наблюдения: $WATCH_DIR" >> "$LOG_FILE"
echo "===========================" >> "$LOG_FILE"

# Снимок существующих файлов
ls "$WATCH_DIR"/*.cap "$WATCH_DIR"/*.pcap 2>/dev/null | sort > /tmp/hs_known.txt

END_TIME=$(($(date +%s) + DURATION * 60))
HS_COUNT=0

LOG "Наблюдение за $WATCH_DIR для обнаружения рукопожатий..."
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

            # Извлечение информации SSID/BSSID
            SSID_INFO=$(aircrack-ng "$CAPFILE" 2>/dev/null | grep -E "^\s+[0-9]+" | head -1)
            BSSID=$(echo "$SSID_INFO" | awk '{print $2}')
            ESSID=$(echo "$SSID_INFO" | awk '{for(i=5;i<=NF;i++) printf $i" "; print ""}' | sed 's/[[:space:]]*$//')
            [ -z "$BSSID" ] && BSSID="неизвестно"
            [ -z "$ESSID" ] && ESSID="неизвестно"

            # Проверка рукопожатия, если включено
            if [ $DO_VALIDATE -eq 1 ]; then
                if aircrack-ng "$CAPFILE" 2>/dev/null | grep -q "1 handshake"; then
                    VALID="ДЕЙСТВИТЕЛЬНО"
                else
                    VALID="нет рукопожатия"
                fi
            fi

            HS_COUNT=$((HS_COUNT + 1))
            echo "[$TIMESTAMP] $FNAME SSID:$ESSID BSSID:$BSSID [$VALID]" >> "$LOG_FILE"
            LOG "Найдено рукопожатие: $ESSID"

            SPINNER_STOP
            PROMPT "⚠ ЗАХВАЧЕНО РУКОПОЖАТИЕ!

Файл: $FNAME
SSID: $ESSID
BSSID: $BSSID
Статус: $VALID
Время: $TIMESTAMP

Всего захватов: $HS_COUNT

Нажмите ОК для продолжения."
            SPINNER_START "Наблюдение..."
        done <<< "$NEW_FILES"

        cp /tmp/hs_current.txt /tmp/hs_known.txt
    fi

    sleep 5
done

SPINNER_STOP
rm -f /tmp/hs_known.txt /tmp/hs_current.txt

echo "===========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Найдено рукопожатий: $HS_COUNT" >> "$LOG_FILE"

PROMPT "НАБЛЮДЕНИЕ ЗАВЕРШЕНО

Длительность: ${DURATION} мин
Найдено рукопожатий: $HS_COUNT

Журнал сохранён в:
$LOG_FILE

Нажмите ОК для выхода."