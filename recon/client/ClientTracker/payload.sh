#!/bin/bash
# Title: Трекер Клиентов
# Author: bad-antics
# Description: Отслеживание определенного устройства по сетям
# Category: nullsec/recon

# ========== FIXES FOR UI ==========
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH

# Fallback UI functions
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v ALERT >/dev/null 2>&1 || ALERT() { echo "[ALERT] $1"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " c; [ "$c" = "y" ] && echo "$DUCKYSCRIPT_USER_CONFIRMED" || echo "$DUCKYSCRIPT_NOT_CONFIRMED"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Value: " val; echo "${val:-$2}"; }
command -v MAC_PICKER >/dev/null 2>&1 || MAC_PICKER() { echo "$1"; read -p "MAC address: " mac; echo "$mac"; }
# Constants if not defined
[ -z "$DUCKYSCRIPT_USER_CONFIRMED" ] && DUCKYSCRIPT_USER_CONFIRMED=0
[ -z "$DUCKYSCRIPT_NOT_CONFIRMED" ] && DUCKYSCRIPT_NOT_CONFIRMED=1
# =================================

# Autodetect wireless interface
if [ -f /root/payloads/library/nullsec-iface.sh ]; then
    . /root/payloads/library/nullsec-iface.sh
    nullsec_require_iface || exit 1
    IFACE="$IFACE"
else
    # Fallback: try to find monitor interface
    IFACE=""
    for i in wlan1mon mon0 wlan0mon; do
        if [ -d "/sys/class/net/$i" ]; then
            IFACE="$i"
            break
        fi
    done
    if [ -z "$IFACE" ]; then
        ERROR_DIALOG "Не найден интерфейс монитора. Создайте mon0: iw dev wlan0 interface add mon0 type monitor"
        exit 1
    fi
fi

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
        # Use iw instead of iwconfig
        iw dev "$IFACE" set channel "$CH" 2>/dev/null
        
        # Capture for 2 seconds
        timeout 2 tcpdump -i "$IFACE" -c 50 -e 2>/dev/null | grep -i "$TARGET_MAC" > /tmp/track_result.txt
        
        if [ -s /tmp/track_result.txt ]; then
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            
            # Try to get BSSID – use airodump-ng limited to 2 sec
            BSSID=""
            timeout 3 airodump-ng "$IFACE" --write-interval 1 -w /tmp/quickscan --output-format csv 2>/dev/null
            if [ -f /tmp/quickscan-01.csv ]; then
                BSSID=$(grep -i "$TARGET_MAC" /tmp/quickscan-01.csv 2>/dev/null | head -1 | cut -d',' -f6 | tr -d ' ')
            fi
            
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
exit 0
