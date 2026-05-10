#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Название: Оповещение о ложных точках доступа
# Автор: NullSec
# Описание: Обнаружение ложных/двойниковых точек доступа и подмены SSID
# Категория: nullsec/alerts

LOOT_DIR="/mmc/nullsec/rogueapalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О ЛОЖНЫХ ТД

Обнаружение двойниковых и
ложных точек доступа путём
сравнения отсканированных ТД
с известным доверенным списком.

Возможности:
- Обнаружение подмены SSID
- Обнаружение дубликатов BSSID
- Оповещения о новых ТД
- Базовый уровень доверенных ТД

Нажмите ОК для настройки."

MON_IF=""
for iface in wlan1mon wlan2mon wlan0mon; do
    [ -d "/sys/class/net/$iface" ] && MON_IF="$iface" && break
done
[ -z "$MON_IF" ] && { ERROR_DIALOG "Интерфейс мониторинга не найден!

Выполните: airmon-ng start wlan1"; exit 1; }

TRUSTED_FILE="$LOOT_DIR/trusted_aps.txt"

PROMPT "РЕЖИМ БАЗОВОГО УРОВНЯ:

1. Сканировать и установить базовый уровень сейчас
2. Использовать существующий доверенный список
3. Мониторинг определённого SSID

Выберите следующий режим."

MODE=$(NUMBER_PICKER "Режим (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MODE=1 ;; esac

WATCH_SSID=""

if [ "$MODE" -eq 1 ]; then
    SPINNER_START "Сканирование доверенного базового уровня..."
    rm -f /tmp/rogue_base*
    timeout 15 airodump-ng "$MON_IF" -w /tmp/rogue_base --output-format csv 2>/dev/null &
    sleep 15
    killall airodump-ng 2>/dev/null
    SPINNER_STOP

    echo "# Доверенный базовый уровень ТД - $(date)" > "$TRUSTED_FILE"
    BASE_COUNT=0
    if [ -f /tmp/rogue_base-01.csv ]; then
        while IFS=',' read -r bssid x1 x2 channel x3 privacy x5 x6 power x7 x8 x9 x10 essid rest; do
            bssid=$(echo "$bssid" | tr -d ' ')
            [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
            essid=$(echo "$essid" | sed 's/^[[:space:]]*//')
            channel=$(echo "$channel" | tr -d ' ')
            echo "$bssid|$essid|$channel" >> "$TRUSTED_FILE"
            BASE_COUNT=$((BASE_COUNT + 1))
        done < /tmp/rogue_base-01.csv
    fi
    rm -f /tmp/rogue_base*
    LOG "Базовый уровень: $BASE_COUNT ТД"
elif [ "$MODE" -eq 2 ]; then
    [ ! -f "$TRUSTED_FILE" ] && { ERROR_DIALOG "Доверенный список не найден!

Сначала выполните сканирование
базового уровня."; exit 1; }
    BASE_COUNT=$(grep -c '^[0-9A-Fa-f]' "$TRUSTED_FILE" 2>/dev/null || echo 0)
elif [ "$MODE" -eq 3 ]; then
    WATCH_SSID="NullSec"
    PROMPT "Введите SSID для отслеживания
двойников на следующем
экране."
    # Создание минимального базового уровня для отслеживаемого SSID
    SPINNER_START "Сканирование $WATCH_SSID..."
    rm -f /tmp/rogue_base*
    timeout 10 airodump-ng "$MON_IF" -w /tmp/rogue_base --output-format csv 2>/dev/null &
    sleep 10
    killall airodump-ng 2>/dev/null
    SPINNER_STOP

    echo "# Базовый уровень отслеживания SSID - $(date)" > "$TRUSTED_FILE"
    BASE_COUNT=0
    if [ -f /tmp/rogue_base-01.csv ]; then
        while IFS=',' read -r bssid x1 x2 channel x3 privacy x5 x6 power x7 x8 x9 x10 essid rest; do
            bssid=$(echo "$bssid" | tr -d ' ')
            [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
            echo "$bssid|$(echo "$essid" | sed 's/^[[:space:]]*//')|$(echo "$channel" | tr -d ' ')" >> "$TRUSTED_FILE"
            BASE_COUNT=$((BASE_COUNT + 1))
        done < /tmp/rogue_base-01.csv
    fi
    rm -f /tmp/rogue_base*
fi

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ НАБЛЮДЕНИЕ ЗА ЛОЖНЫМИ ТД?

Доверенных ТД: $BASE_COUNT
Длительность: ${DURATION} мин
$([ -n "$WATCH_SSID" ] && echo "Отслеживание SSID: $WATCH_SSID")

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/rogue_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О ЛОЖНЫХ ТД ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "ТД в базовом уровне: $BASE_COUNT" >> "$LOG_FILE"
echo "==========================" >> "$LOG_FILE"

END_TIME=$(($(date +%s) + DURATION * 60))
ROGUE_COUNT=0

LOG "Наблюдение за ложными ТД..."
SPINNER_START "Сканирование ложных ТД..."

while [ $(date +%s) -lt $END_TIME ]; do
    rm -f /tmp/rogue_scan*
    timeout 10 airodump-ng "$MON_IF" -w /tmp/rogue_scan --output-format csv 2>/dev/null &
    sleep 10
    killall airodump-ng 2>/dev/null

    if [ -f /tmp/rogue_scan-01.csv ]; then
        while IFS=',' read -r bssid x1 x2 channel x3 privacy x5 x6 power x7 x8 x9 x10 essid rest; do
            bssid=$(echo "$bssid" | tr -d ' ')
            [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
            essid=$(echo "$essid" | sed 's/^[[:space:]]*//')
            channel=$(echo "$channel" | tr -d ' ')

            # Проверка, известен ли BSSID
            if ! grep -qi "$bssid" "$TRUSTED_FILE" 2>/dev/null; then
                # Неизвестный BSSID - проверка, совпадает ли SSID с известным (двойник)
                if grep -qi "|${essid}|" "$TRUSTED_FILE" 2>/dev/null; then
                    ROGUE_COUNT=$((ROGUE_COUNT + 1))
                    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
                    echo "[$TIMESTAMP] ДВОЙНИК: $essid BSSID:$bssid Кан:$channel" >> "$LOG_FILE"
                    LOG "ЛОЖНАЯ ТД: Двойник $essid"

                    SPINNER_STOP
                    PROMPT "⚠ ОБНАРУЖЕН ДВОЙНИК!

SSID: $essid
BSSID двойника: $bssid
Канал: $channel

Эта ТД подменяет имя
доверенной сети!

Найдено двойников: $ROGUE_COUNT

Нажмите ОК для продолжения."
                    SPINNER_START "Сканирование..."
                fi
            fi
        done < /tmp/rogue_scan-01.csv
    fi
    rm -f /tmp/rogue_scan*
done

SPINNER_STOP

echo "==========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Обнаружено двойников: $ROGUE_COUNT" >> "$LOG_FILE"

PROMPT "НАБЛЮДЕНИЕ ЗА ЛОЖНЫМИ ТД ЗАВЕРШЕНО

Длительность: ${DURATION} мин
Обнаружено двойников: $ROGUE_COUNT

Журнал сохранён в:
$LOG_FILE

Нажмите ОК для выхода."