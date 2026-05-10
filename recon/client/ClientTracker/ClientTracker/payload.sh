#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Трекер Клиентов
# Author: bad-antics
# Description: Отслеживание определенного устройства по сетям
# Category: nullsec/recon

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/tracking"
mkdir -p "$LOOT_DIR"

PROMPT "ТРЕКЕР КЛИЕНТОВ

Мониторинг подключения
определенного устройства
к любой WiFi сети.

Отслеживание телефонов,
ноутбуков, IoT устройств и т.д.

Нажмите OK для настройки."

TARGET_MAC=$(MAC_PICKER "Целевой MAC устройства:")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) 
    ERROR_DIALOG "Требуется MAC!"
    exit 1
    ;;
esac

DURATION=$(NUMBER_PICKER "Длительность отслеживания (мин):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac

ALERT_MODE=$(CONFIRMATION_DIALOG "Оповещение при обнаружении?

Вибрация/звук при
обнаружении цели?")

LOG_FILE="$LOOT_DIR/track_${TARGET_MAC//:/}_$(date +%Y%m%d_%H%M).txt"

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ОТСЛЕЖИВАНИЕ?

Цель: $TARGET_MAC
Длительность: ${DURATION} мин
Лог: $LOG_FILE

Нажмите OK для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

echo "=== ЖУРНАЛ ОТСЛЕЖИВАНИЯ КЛИЕНТОВ ===" > "$LOG_FILE"
echo "Цель: $TARGET_MAC" >> "$LOG_FILE"
echo "Начато: $(date)" >> "$LOG_FILE"
echo "=========================" >> "$LOG_FILE"

END_TIME=$(($(date +%s) + DURATION * 60))
DETECTIONS=0
LAST_SEEN=""

LOG "Отслеживание $TARGET_MAC..."

while [ $(date +%s) -lt $END_TIME ]; do
    # Quick scan all channels
    for CH in 1 6 11; do
        iwconfig $IFACE channel $CH 2>/dev/null
        
        # Capture for 2 seconds
        timeout 2 tcpdump -i $IFACE -c 50 -e 2>/dev/null | grep -i "$TARGET_MAC" > /tmp/track_result.txt
        
        if [ -s /tmp/track_result.txt ]; then
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            
            # Try to get BSSID
            BSSID=$(timeout 3 airodump-ng $IFACE --write-interval 1 -w /tmp/quickscan --output-format csv 2>/dev/null; grep -i "$TARGET_MAC" /tmp/quickscan*.csv 2>/dev/null | head -1 | cut -d',' -f6 | tr -d ' ')
            
            if [ "$LAST_SEEN" != "$CH-$BSSID" ]; then
                DETECTIONS=$((DETECTIONS + 1))
                LAST_SEEN="$CH-$BSSID"
                
                echo "[$TIMESTAMP] Канал:$CH BSSID:$BSSID" >> "$LOG_FILE"
                
                if [ "$ALERT_MODE" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
                    ALERT "Цель обнаружена! Канал:$CH"
                fi
                
                LOG "Обнаружено на канале $CH"
            fi
        fi
    done
    
    sleep 1
done

echo "=========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Всего обнаружений: $DETECTIONS" >> "$LOG_FILE"

PROMPT "ОТСЛЕЖИВАНИЕ ЗАВЕРШЕНО

Цель: $TARGET_MAC
Длительность: ${DURATION} мин
Обнаружений: $DETECTIONS

Лог сохранен в:
$LOG_FILE

Нажмите OK для выхода."
