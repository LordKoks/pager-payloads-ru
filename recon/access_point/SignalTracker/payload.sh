#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Трекер сигнала
# Author: bad-antics
# Description: Отслеживание уровня сигнала для физического поиска точек доступа и клиентов
# Category: nullsec/recon

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ТРЕКЕР СИГНАЛА

Отслеживает уровень WiFi-сигнала
для физического поиска
точек доступа или клиентов.

Полезно для поиска скрытых
устройств или rogue-точек.

Нажми OK для продолжения."

INTERFACE="$IFACE"
MODE=$(NUMBER_PICKER "Отслеживать: 1=Точка доступа  2=Клиент" 1)

# Останавливаем мешающие процессы
airmon-ng check kill 2>/dev/null
sleep 1

# Включаем режим монитора
airmon-ng start $INTERFACE >/dev/null 2>&1
MON_IF="${INTERFACE}mon"
[ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"

SPINNER_START "Сканирование..."

# Быстрое сканирование
TEMP_DIR="/tmp/sigtrack_$$"
mkdir -p "$TEMP_DIR"
timeout 10 airodump-ng $MON_IF -w "$TEMP_DIR/scan" --output-format csv 2>/dev/null &
sleep 10

SPINNER_STOP

if [ "$MODE" = "1" ]; then
    # Список точек доступа
    APS=$(grep -E "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" "$TEMP_DIR/scan-01.csv" 2>/dev/null | grep -v "Station MAC" | head -10)
    
    PROMPT "ВЫБЕРИ ЦЕЛЕВУЮ ТОЧКУ ДОСТУПА:

$(echo "$APS" | awk -F',' '{printf "%s %s\n", $1, $14}' | head -10)

Введи BSSID для отслеживания."

    TARGET=$(MAC_PICKER "BSSID цели:")
else
    # Список клиентов
    CLIENTS=$(grep -E "^[0-9A-Fa-f]{2}:" "$TEMP_DIR/scan-01.csv" 2>/dev/null | grep "," | head -10)
    
    PROMPT "ВЫБЕРИ ЦЕЛЕВОГО КЛИЕНТА:

$(echo "$CLIENTS" | awk -F',' '{print $1}' | head -10)

Введи MAC-адрес для отслеживания."

    TARGET=$(MAC_PICKER "MAC клиента:")
fi

PROMPT "ОТСЛЕЖИВАНИЕ: $TARGET

Перемещай устройство.
Уровень сигнала будет обновляться.

Чем сильнее сигнал — тем ближе
ты к целевому устройству.

Нажми OK для запуска."

# Получаем канал цели
if [ "$MODE" = "1" ]; then
    CHANNEL=$(grep "$TARGET" "$TEMP_DIR/scan-01.csv" | head -1 | cut -d',' -f4 | tr -d ' ')
else
    CHANNEL=$(TEXT_PICKER "Канал:" "6")
fi

iwconfig $MON_IF channel $CHANNEL 2>/dev/null

# Цикл отслеживания сигнала
for i in {1..30}; do
    SIGNAL=$(timeout 2 airodump-ng $MON_IF -c $CHANNEL --bssid "$TARGET" 2>&1 | grep -o "\-[0-9]*" | head -1)
    
    if [ -n "$SIGNAL" ]; then
        ABS_SIG=$(echo "$SIGNAL" | tr -d '-')
        if [ "$ABS_SIG" -lt 50 ]; then
            BARS="█████ ОЧЕНЬ БЛИЗКО!"
        elif [ "$ABS_SIG" -lt 60 ]; then
            BARS="████░ БЛИЗКО"
        elif [ "$ABS_SIG" -lt 70 ]; then
            BARS="███░░ СРЕДНЕ"
        elif [ "$ABS_SIG" -lt 80 ]; then
            BARS="██░░░ ДАЛЕКО"
        else
            BARS="█░░░░ ОЧЕНЬ ДАЛЕКО"
        fi
        
        LOG "Сигнал: ${SIGNAL} dBm $BARS"
    else
        LOG "Сигнал не обнаружен..."
    fi
    
    sleep 2
done

# Очистка
airmon-ng stop $MON_IF 2>/dev/null
rm -rf "$TEMP_DIR"

PROMPT "ОТСЛЕЖИВАНИЕ ЗАВЕРШЕНО

Цель: $TARGET
Последний сигнал: ${SIGNAL:-N/A} dBm

Используй только для
легитимного поиска устройств.

Нажми OK для выхода."