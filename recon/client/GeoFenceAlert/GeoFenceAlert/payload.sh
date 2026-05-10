#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: GeoFence Alert
# Author: NullSec
# Description: Слежение за геозоной с предупреждениями о входе/выходе устройств
# Category: nullsec/alerts

LOOT_DIR="/mmc/nullsec/geofencealert"
mkdir -p "$LOOT_DIR"

PROMPT "GEOFENCE ALERT

Система оповещений по GPS и WiFi.
Отслеживает вход и выход
из заданной зоны.

Функции:
- Геозонный контроль по GPS
- Отслеживание MAC-устройств
- Определение входа/выхода
- Настройка радиуса

Нажмите OK для настройки."

# Check for GPS device
GPS_DEV=""
for dev in /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyS0; do
    [ -e "$dev" ] && GPS_DEV="$dev" && break
done

if [ -z "$GPS_DEV" ]; then
    resp=$(CONFIRMATION_DIALOG "GPS-устройство не найдено!

Продолжить без GPS?
Будет использовано только
определение по WiFi.")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0
    GPS_MODE=0
else
    GPS_MODE=1
    LOG "GPS устройство: $GPS_DEV"
fi

# Monitor interface
MON_IF=""
for iface in wlan1mon wlan2mon wlan0mon; do
    [ -d "/sys/class/net/$iface" ] && MON_IF="$iface" && break
done
[ -z "$MON_IF" ] && { ERROR_DIALOG "Нет интерфейса мониторинга!

Запустите: airmon-ng start wlan1"; exit 1; }

# Parse NMEA GPS data
get_gps_coords() {
    if [ "$GPS_MODE" -eq 1 ]; then
        NMEA=$(timeout 3 cat "$GPS_DEV" 2>/dev/null | grep '^\$GPGGA' | head -1)
        if [ -n "$NMEA" ]; then
            LAT=$(echo "$NMEA" | cut -d',' -f3)
            LAT_DIR=$(echo "$NMEA" | cut -d',' -f4)
            LON=$(echo "$NMEA" | cut -d',' -f5)
            LON_DIR=$(echo "$NMEA" | cut -d',' -f6)
            echo "$LAT$LAT_DIR,$LON$LON_DIR"
        else
            echo "no_fix"
        fi
    else
        echo "no_gps"
    fi
}

PROMPT "РАДИУС ЗОНЫ:

Зона близости по сигналу
(порог dBm).

1. Близко  (-50 dBm)
2. Средне (-65 dBm)
3. Далеко  (-80 dBm)

Выберите диапазон."

RANGE_SEL=$(NUMBER_PICKER "Диапазон (1-3):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) RANGE_SEL=2 ;; esac

case $RANGE_SEL in
    1) SIGNAL_THRESH=-50 ;;
    2) SIGNAL_THRESH=-65 ;;
    3) SIGNAL_THRESH=-80 ;;
    *) SIGNAL_THRESH=-65 ;;
esac

PROMPT "ЦЕЛЕВЫЕ УСТРОЙСТВА:

Сканировать сейчас, чтобы собрать
список устройств в зоне.
Они будут отслеживаться
в геозоне.

Нажмите OK для сканирования."

SPINNER_START "Сканирование устройств..."
rm -f /tmp/geo_scan*
timeout 15 airodump-ng "$MON_IF" -w /tmp/geo_scan --output-format csv 2>/dev/null &
sleep 15
killall airodump-ng 2>/dev/null
SPINNER_STOP

DEVICE_FILE="$LOOT_DIR/tracked_devices.txt"
echo "# Tracked Devices - $(date)" > "$DEVICE_FILE"
DEV_COUNT=0

# Parse client section of airodump CSV
if [ -f /tmp/geo_scan-01.csv ]; then
    IN_CLIENTS=0
    while IFS=',' read -r field1 field2 field3 rest; do
        field1=$(echo "$field1" | tr -d ' ')
        if echo "$field1" | grep -q "Station"; then
            IN_CLIENTS=1
            continue
        fi
        [ $IN_CLIENTS -eq 0 ] && continue
        [[ ! "$field1" =~ ^[0-9A-Fa-f]{2}: ]] && continue
        power=$(echo "$field2" | tr -d ' ')
        [ -z "$power" ] && continue
        DEV_COUNT=$((DEV_COUNT + 1))
        echo "$field1|$power" >> "$DEVICE_FILE"
        [ $DEV_COUNT -ge 20 ] && break
    done < /tmp/geo_scan-01.csv
fi
rm -f /tmp/geo_scan*

[ $DEV_COUNT -eq 0 ] && { ERROR_DIALOG "Устройств не найдено!

Попробуйте сканировать
в более заполненном месте."; exit 1; }

DURATION=$(NUMBER_PICKER "Мониторинг (минуты):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ GEOFENCE?

Отслеживаемых устройств: $DEV_COUNT
Порог сигнала: $SIGNAL_THRESH dBm
Время: ${DURATION} мин
GPS: $([ $GPS_MODE -eq 1 ] && echo ВКЛ || echo ВЫКЛ)

Нажмите OK для запуска.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/geofence_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ GEOFENCE ===" > "$LOG_FILE"
echo "Начато: $(date)" >> "$LOG_FILE"
echo "Устройств: $DEV_COUNT" >> "$LOG_FILE"
echo "Порог: $SIGNAL_THRESH dBm" >> "$LOG_FILE"
echo "==========================" >> "$LOG_FILE"

# Track device presence state
> /tmp/geo_present.txt

END_TIME=$(($(date +%s) + DURATION * 60))
ENTER_COUNT=0
LEAVE_COUNT=0

LOG "Мониторинг геозоны ($DEV_COUNT устройств)..."
SPINNER_START "Мониторинг геозоны..."

while [ $(date +%s) -lt $END_TIME ]; do
    COORDS=$(get_gps_coords)

    # Quick scan for device signals
    rm -f /tmp/geo_now*
    timeout 8 airodump-ng "$MON_IF" -w /tmp/geo_now --output-format csv 2>/dev/null &
    sleep 8
    killall airodump-ng 2>/dev/null

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Check each tracked device
    while IFS='|' read -r tracked_mac tracked_init; do
        [ -z "$tracked_mac" ] && continue
        [[ "$tracked_mac" =~ ^# ]] && continue

        # Search for this MAC in current scan
        CURRENT_POWER=""
        if [ -f /tmp/geo_now-01.csv ]; then
            CURRENT_POWER=$(grep -i "$tracked_mac" /tmp/geo_now-01.csv 2>/dev/null | \
                head -1 | cut -d',' -f4 | tr -d ' ')
        fi

        WAS_PRESENT=$(grep -c "$tracked_mac" /tmp/geo_present.txt 2>/dev/null)

        if [ -n "$CURRENT_POWER" ] && [ "$CURRENT_POWER" -gt "$SIGNAL_THRESH" ] 2>/dev/null; then
            # Device in range
            if [ "$WAS_PRESENT" -eq 0 ]; then
                ENTER_COUNT=$((ENTER_COUNT + 1))
                echo "$tracked_mac" >> /tmp/geo_present.txt
                echo "[$TIMESTAMP] ВХОД $tracked_mac (${CURRENT_POWER}dBm) GPS:$COORDS" >> "$LOG_FILE"
                LOG "Устройство вошло: $tracked_mac"

                SPINNER_STOP
                PROMPT "⚠ УСТРОЙСТВО ВОШЛО!

MAC: $tracked_mac
Сигнал: ${CURRENT_POWER} dBm
GPS: $COORDS

Входов: $ENTER_COUNT
Выходов: $LEAVE_COUNT

Нажмите OK, чтобы продолжить."
                SPINNER_START "Мониторинг..."
            fi
        else
            # Device out of range
            if [ "$WAS_PRESENT" -gt 0 ]; then
                LEAVE_COUNT=$((LEAVE_COUNT + 1))
                grep -v "$tracked_mac" /tmp/geo_present.txt > /tmp/geo_tmp.txt 2>/dev/null
                mv /tmp/geo_tmp.txt /tmp/geo_present.txt
                echo "[$TIMESTAMP] ВЫХОД $tracked_mac GPS:$COORDS" >> "$LOG_FILE"
                LOG "Устройство вышло: $tracked_mac"

                SPINNER_STOP
                PROMPT "⚠ УСТРОЙСТВО ВЫШЛО!

MAC: $tracked_mac
GPS: $COORDS

Входов: $ENTER_COUNT
Выходов: $LEAVE_COUNT

Нажмите OK, чтобы продолжить."
                SPINNER_START "Мониторинг..."
            fi
        fi
    done < "$DEVICE_FILE"

    rm -f /tmp/geo_now*
done

SPINNER_STOP
rm -f /tmp/geo_present.txt /tmp/geo_now* /tmp/geo_tmp.txt

echo "==========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Входов: $ENTER_COUNT" >> "$LOG_FILE"
echo "Выходов: $LEAVE_COUNT" >> "$LOG_FILE"

PROMPT "GEOFENCE ЗАВЕРШЕН

Длительность: ${DURATION} мин
Отслеживаемых устройств: $DEV_COUNT
Входов: $ENTER_COUNT
Выходов: $LEAVE_COUNT

Журнал сохранен:
$LOG_FILE

Нажмите OK для выхода."
