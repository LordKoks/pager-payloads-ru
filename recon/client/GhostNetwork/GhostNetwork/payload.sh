#!/bin/sh
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
#####################################################
# NullSec GhostСеть Payload
# Создает скрытую секретную сеть для скрытого C2
#####################################################
# Author: NullSec Team
# Target: WiFi Pineapple Pager
# Category: Stealth/Covert
#####################################################

PAYLOAD_NAME="GhostСеть"
source /root/payloads/library/nullsec-lib.sh 2>/dev/null || true

# Конфигурация
GHOST_SSID="\x00\x00\x00\x00\x00\x00\x00\x00"  # Нулевые байты - невидимая сеть
GHOST_CHANNEL="${TARGET_CHANNEL:-6}"
GHOST_INTERFACE="wlan1"
BEACON_INTERVAL="1000"  # Более редкий маяк = сложнее обнаружить
LOOT_DIR="/root/loot/ghost"
LOG_FILE="$LOOT_DIR/ghost_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOOT_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "[!] Очищаю ghost-сеть..."
    killall hostapd 2>/dev/null
    ifconfig "$GHOST_INTERFACE" down 2>/dev/null
    log "[*] Ghost-сеть завершена"
    exit 0
}

trap cleanup INT TERM

log "=========================================="
log "   NullSec GhostСеть v1.0"
log "=========================================="
log "[*] Создаю невидимую скрытую сеть..."

# Проверка интерфейса
if ! ifconfig "$GHOST_INTERFACE" >/dev/null 2>&1; then
    log "[!] Интерфейс $GHOST_INTERFACE не найден"
    exit 1
fi

# Создание конфигурации hostapd для скрытой сети
HOSTAPD_CONF="/tmp/ghost_hostapd.conf"
cat > "$HOSTAPD_CONF" << EOF
interface=$GHOST_INTERFACE
driver=nl80211
ssid=$GHOST_SSID
channel=$GHOST_CHANNEL
hw_mode=g
ieee80211n=1
ignore_broadcast_ssid=2
beacon_int=$BEACON_INTERVAL
auth_algs=1
wpa=0
EOF

# Запуск ghost AP
log "[*] Запускаю ghost AP на канале $GHOST_CHANNEL..."
ifconfig "$GHOST_INTERFACE" up
hostapd -B "$HOSTAPD_CONF" 2>/dev/null

if [ $? -eq 0 ]; then
    log "[+] Ghost-сеть активна (скрытый SSID)"
    log "[*] Предварительно общий ключ для клиентов: nullsec_ghost"
    log "[*] Клиенты должны знать SSID для подключения"
    
    # Настройка простого DHCP
    ifconfig "$GHOST_INTERFACE" 10.66.66.1 netmask 255.255.255.0
    
    # Мониторинг подключений
    log "[*] Мониторю ghost-клиентов..."
    while true; do
        CLIENTS=$(iw dev "$GHOST_INTERFACE" station dump 2>/dev/null | grep Station | wc -l)
        if [ "$CLIENTS" -gt 0 ]; then
            log "[+] Ghost-клиентов подключено: $CLIENTS"
            iw dev "$GHOST_INTERFACE" station dump >> "$LOG_FILE" 2>/dev/null
        fi
        sleep 30
    done
else
    log "[!] Не удалось запустить ghost-сеть"
    exit 1
fi
