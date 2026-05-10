#!/bin/sh
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
#####################################################
# NullSec SocialMapper
# Карта социальных связей и отношений устройств
#####################################################
# Автор: NullSec Team
# Цель: WiFi Pineapple Pager
# Категория: OSINT / Разведка
#####################################################

PAYLOAD_NAME="SocialMapper"
source /root/payloads/library/nullsec-lib.sh 2>/dev/null || true

# Настройки
MONITOR_INTERFACE="wlan1mon"
LOOT_DIR="/root/loot/socialmap"
LOG_FILE="$LOOT_DIR/socialmap_$(date +%Y%m%d_%H%M%S).log"
SCAN_TIME="${1:-120}"  # Длительность сканирования в секундах
MAP_FILE="$LOOT_DIR/network_map_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$LOOT_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "[!] Остановка SocialMapper..."
    killall airodump-ng 2>/dev/null
    airmon-ng stop "$MONITOR_INTERFACE" 2>/dev/null
    generate_report
    exit 0
}

get_vendor() {
    MAC_PREFIX=$(echo "$1" | cut -d':' -f1-3 | tr 'a-f' 'A-F')
    case "$MAC_PREFIX" in
        "00:00:0C"|"00:1A:A1"|"00:26:CB") echo "Cisco" ;;
        "00:17:C4"|"00:1D:4F"|"78:7B:8A") echo "Quanta/Apple" ;;
        "00:03:93"|"00:0D:93"|"00:26:08") echo "Apple" ;;
        "00:1A:11"|"34:23:87"|"70:56:81") echo "Google" ;;
        "B4:F0:AB"|"B8:27:EB"|"DC:A6:32") echo "Raspberry Pi" ;;
        "00:50:56"|"00:0C:29"|"00:15:5D") echo "VMware/Hyper-V" ;;
        "00:1E:C2"|"3C:D9:2B"|"00:26:5A") echo "Samsung" ;;
        "F8:1E:DF"|"3C:15:C2"|"CC:08:E0") echo "Apple" ;;
        "AC:BC:32"|"00:25:00"|"7C:E9:D3") echo "Apple" ;;
        *) echo "Неизвестный" ;;
    esac
}

generate_report() {
    log ""
    log "=========================================="
    log "   Отчёт карты социальных связей"
    log "=========================================="
    
    if [ ! -f "$LOOT_DIR/temp_scan-01.csv" ]; then
        log "[!] Нет данных сканирования"
        return
    fi
    
    echo "NullSec Social Сеть Map" > "$MAP_FILE"
    echo "Сгенерировано: $(date)" >> "$MAP_FILE"
    echo "==========================================" >> "$MAP_FILE"
    echo "" >> "$MAP_FILE"
    
    # Точки доступа
    echo "=== ТОЧКИ ДОСТУПА ===" >> "$MAP_FILE"
    grep -E "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}.*," "$LOOT_DIR/temp_scan-01.csv" 2>/dev/null | \
    head -20 | while IFS=',' read -r BSSID FIRST LAST CHANNEL SPEED PRIVACY CIPHER AUTH POWER BEACONS IV LAN IDLEN ESSID REST; do
        BSSID=$(echo "$BSSID" | tr -d ' ')
        ESSID=$(echo "$ESSID" | tr -d ' ')
        [ -z "$BSSID" ] && continue
        [ "$BSSID" = "BSSID" ] && continue
        
        VENDOR=$(get_vendor "$BSSID")
        CLIENT_COUNT=$(grep -c "$BSSID" "$LOOT_DIR/temp_scan-01.csv" 2>/dev/null)
        
        echo "" >> "$MAP_FILE"
        echo "[$ESSID]" >> "$MAP_FILE"
        echo "  BSSID: $BSSID" >> "$MAP_FILE"
        echo "  Производитель: $VENDOR" >> "$MAP_FILE"
        echo "  Канал: $CHANNEL | Защита: $PRIVACY" >> "$MAP_FILE"
        echo "  Подключённых клиентов: ~$CLIENT_COUNT" >> "$MAP_FILE"
        
        log "[+] Сеть: $ESSID ($BSSID) — $VENDOR"
    done
    
    # Клиенты и их связи
    echo "" >> "$MAP_FILE"
    echo "=== СВЯЗИ КЛИЕНТОВ ===" >> "$MAP_FILE"
    
    CLIENTS=$(awk '/Station MAC/,/^$/' "$LOOT_DIR/temp_scan-01.csv" 2>/dev/null | tail -n +2)
    
    echo "$CLIENTS" | while IFS=',' read -r CLIENT_MAC FIRST LAST POWER PACKETS BSSID PROBES; do
        CLIENT_MAC=$(echo "$CLIENT_MAC" | tr -d ' ')
        BSSID=$(echo "$BSSID" | tr -d ' ')
        PROBES=$(echo "$PROBES" | tr -d ' ')
        
        [ -z "$CLIENT_MAC" ] && continue
        
        VENDOR=$(get_vendor "$CLIENT_MAC")
        
        echo "" >> "$MAP_FILE"
        echo "Клиент: $CLIENT_MAC ($VENDOR)" >> "$MAP_FILE"
        
        if [ "$BSSID" != "(not associated)" ] && [ -n "$BSSID" ]; then
            ASSOC_ESSID=$(grep "$BSSID" "$LOOT_DIR/temp_scan-01.csv" | head -1 | cut -d',' -f14 | tr -d ' ')
            echo "  → Подключён к: $ASSOC_ESSID ($BSSID)" >> "$MAP_FILE"
        fi
        
        if [ -n "$PROBES" ]; then
            echo "  → Пробует сети: $PROBES" >> "$MAP_FILE"
            PROBE_COUNT=$(echo "$PROBES" | tr ',' '\n' | wc -l)
            echo "  → История сетей: $PROBE_COUNT известных сетей" >> "$MAP_FILE"
        fi
        
        log "[*] Клиент: $CLIENT_MAC ($VENDOR) пробует: $PROBES"
    done
    
    # Статистика
    echo "" >> "$MAP_FILE"
    echo "=== СТАТИСТИКА ===" >> "$MAP_FILE"
    AP_COUNT=$(grep -cE "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}.*," "$LOOT_DIR/temp_scan-01.csv" 2>/dev/null)
    CLIENT_COUNT=$(echo "$CLIENTS" | grep -cE "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
    echo "Всего точек доступа: $AP_COUNT" >> "$MAP_FILE"
    echo "Всего клиентов: $CLIENT_COUNT" >> "$MAP_FILE"
    
    log ""
    log "[+] Карта сохранена в: $MAP_FILE"
    log "[*] Всего точек доступа: $AP_COUNT"
    log "[*] Всего клиентов: $CLIENT_COUNT"
}

trap cleanup INT TERM

log "=========================================="
log "   NullSec SocialMapper v1.0"
log "=========================================="
log "[*] Длительность сканирования: ${SCAN_TIME} сек"
log "[*] Построение карты социальных связей..."

# Настройка режима монитора
airmon-ng start wlan1 2>/dev/null
sleep 2

# Сканирование всех каналов
log "[*] Сканирование всех каналов для поиска устройств и связей..."

airodump-ng "$MONITOR_INTERFACE" \
    --write "$LOOT_DIR/temp_scan" \
    --output-format csv \
    --write-interval 5 2>/dev/null &
SCAN_PID=$!

# Индикатор прогресса
ELAPSED=0
while [ $ELAPSED -lt $SCAN_TIME ]; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    
    if [ -f "$LOOT_DIR/temp_scan-01.csv" ]; then
        CURRENT_APS=$(grep -cE "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}.*," "$LOOT_DIR/temp_scan-01.csv" 2>/dev/null)
        log "[*] Прогресс: ${ELAPSED}с / ${SCAN_TIME}с — Найдено $CURRENT_APS сетей"
    fi
done

kill $SCAN_PID 2>/dev/null
sleep 2

cleanup