#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Сканер IoT устройств
# Author: bad-antics
# Description: Поиск и определение умных устройств (камеры, умные колонки, розетки и т.д.)
# Category: nullsec/recon

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "СКАНЕР IoT УСТРОЙСТВ

Обнаруживает умные устройства:
- Умные телевизоры
- IP-камеры
- Умные розетки
- Термостаты
- Голосовые помощники
- и другие IoT-девайсы

Нажми OK для продолжения."

INTERFACE="$IFACE"
LOOT_DIR="/mmc/nullsec/iot"
mkdir -p "$LOOT_DIR"
LOOT_FILE="$LOOT_DIR/iot_$(date +%Y%m%d_%H%M%S).txt"

PROMPT "РЕЖИМ СКАНИРОВАНИЯ:

1. Пассивный (тихий)
2. Активный (полный)
3. Комбинированный

Пассивный = скрытно
Активный = максимально подробно

Выбери режим:"

SCAN_MODE=$(NUMBER_PICKER "Режим (1-3):" 3)

# База известных IoT устройств (OUI + SSID)
IOT_OUIS="18:B4:30:Nest
64:16:66:Nest
F4:F5:D8:Google Home
20:DF:B9:Google Home
30:FD:38:Google Home
48:D6:D5:Amazon Echo
50:DC:E7:Amazon
68:37:E9:Amazon
FC:65:DE:Amazon
44:65:0D:Amazon
00:FC:8B:Amazon
00:17:88:Philips Hue
EC:B5:FA:Philips Hue
00:24:88:Ring
9C:02:98:Ring
94:10:3E:Ring
50:14:79:TP-Link
B0:BE:76:TP-Link
60:01:94:TP-Link
D8:0D:17:TP-Link
70:4F:57:TP-Link
74:DA:38:EZVIZ
8C:7A:15:Roku
B0:A7:B9:Roku
DC:3A:5E:Roku
D8:31:34:Roku
70:A7:93:Roku
84:EA:64:Roku
14:91:82:Belkin WeMo
94:10:3E:Belkin
EC:1A:59:Belkin
C4:41:1E:Belkin
78:4B:87:Wink
88:D7:F6:Apple HomeKit
9C:20:7B:Apple HomeKit
D0:5F:B8:Apple HomeKit
60:3C:92:Wyze
2C:AA:8E:Wyze
7C:78:B2:Wyze
AC:ED:5C:Insteon
D0:73:D5:LiFX
00:22:6D:August Lock
38:B1:DB:August Lock
F0:45:DA:Samsung SmartThings"

IOT_SSIDS="RING-|Ring-|NEST-|Nest-|Wyze|ECHO-|echo-|SmartThings|HUE-|Philips|WeMo|MyQ|DIRECTV|Roku|Fire-TV|Amazon-|LIFX|Sonos"

echo "=== Результаты сканирования IoT устройств ===" > "$LOOT_FILE"
echo "Дата: $(date)" >> "$LOOT_FILE"
echo "=====================================" >> "$LOOT_FILE"

FOUND=0

if [ "$SCAN_MODE" = "1" ] || [ "$SCAN_MODE" = "3" ]; then
    # Пассивное сканирование
    airmon-ng check kill 2>/dev/null
    airmon-ng start $INTERFACE >/dev/null 2>&1
    MON_IF="${INTERFACE}mon"
    [ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"
    
    SPINNER_START "Пассивное сканирование (20 сек)..."

    TEMP_DIR="/tmp/iotscan_$$"
    mkdir -p "$TEMP_DIR"
    timeout 20 airodump-ng $MON_IF -w "$TEMP_DIR/scan" --output-format csv 2>/dev/null &
    sleep 20
    
    SPINNER_STOP

    # Обработка результатов
    while IFS=',' read -r BSSID F2 F3 CHANNEL F5 F6 F7 F8 F9 POWER F11 F12 F13 ESSID REST; do
        BSSID=$(echo "$BSSID" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        ESSID=$(echo "$ESSID" | tr -d ' ')
        
        if [ -n "$BSSID" ] && echo "$BSSID" | grep -qE "^[0-9A-Fa-f]{2}:"; then
            OUI=$(echo "$BSSID" | cut -d':' -f1-3)
            
            DEVICE_TYPE=""
            if echo "$IOT_OUIS" | grep -qi "$OUI"; then
                DEVICE_TYPE=$(echo "$IOT_OUIS" | grep -i "$OUI" | head -1 | cut -d':' -f4-)
            fi
            
            if [ -z "$DEVICE_TYPE" ] && echo "$ESSID" | grep -qiE "$IOT_SSIDS"; then
                DEVICE_TYPE="Неизвестное IoT (по SSID)"
            fi
            
            if [ -n "$DEVICE_TYPE" ]; then
                echo "" >> "$LOOT_FILE"
                echo "НАЙДЕНО IoT УСТРОЙСТВО!" >> "$LOOT_FILE"
                echo "Тип: $DEVICE_TYPE" >> "$LOOT_FILE"
                echo "MAC:  $BSSID" >> "$LOOT_FILE"
                echo "SSID: $ESSID" >> "$LOOT_FILE"
                echo "Канал: $CHANNEL" >> "$LOOT_FILE"
                echo "Сигнал: $POWER dBm" >> "$LOOT_FILE"
                echo "----------------------------------------" >> "$LOOT_FILE"
                ((FOUND++))
            fi
        fi
    done < "$TEMP_DIR/scan-01.csv"
    
    rm -rf "$TEMP_DIR"
    airmon-ng stop $MON_IF 2>/dev/null
fi

if [ "$SCAN_MODE" = "2" ] || [ "$SCAN_MODE" = "3" ]; then
    # Активное сканирование
    PROMPT "АКТИВНОЕ СКАНИРОВАНИЕ

Введи диапазон сети для
поиска IoT устройств.

Пример: 192.168.1.0/24"
    
    СЕТЬ=$(TEXT_PICKER "Диапазон сети:" "192.168.1.0/24")
    
    SPINNER_START "Выполняется активное сканирование..."

    echo "" >> "$LOOT_FILE"
    echo "--- Активное сканирование ---" >> "$LOOT_FILE"
    
    ARP_RESULTS=$(arp-scan -I $INTERFACE $СЕТЬ 2>/dev/null || echo "arp-scan недоступен")
    
    echo "$ARP_RESULTS" | while read LINE; do
        IP=$(echo "$LINE" | awk '{print $1}')
        MAC=$(echo "$LINE" | awk '{print $2}' | tr '[:lower:]' '[:upper:]')
        VENDOR=$(echo "$LINE" | awk '{$1=$2=""; print $0}')
        
        if [ -n "$MAC" ] && echo "$MAC" | grep -qE "^[0-9A-Fa-f]{2}:"; then
            OUI=$(echo "$MAC" | cut -d':' -f1-3)
            
            if echo "$IOT_OUIS" | grep -qi "$OUI"; then
                DEVICE_TYPE=$(echo "$IOT_OUIS" | grep -i "$OUI" | head -1 | cut -d':' -f4-)
                echo "" >> "$LOOT_FILE"
                echo "IoT Устройство: $DEVICE_TYPE" >> "$LOOT_FILE"
                echo "IP:   $IP" >> "$LOOT_FILE"
                echo "MAC:  $MAC" >> "$LOOT_FILE"
                echo "Производитель: $VENDOR" >> "$LOOT_FILE"
                ((FOUND++))
            fi
        fi
    done
    
    SPINNER_STOP
fi

PROMPT "СКАНИРОВАНИЕ IoT ЗАВЕРШЕНО

Найдено устройств: $FOUND

Результаты сохранены в:
$LOOT_FILE

Нажми OK для выхода."