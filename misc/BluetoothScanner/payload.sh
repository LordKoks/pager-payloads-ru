#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Bluetooth Scanner
# Author: NullSec
# Description: Bluetooth and BLE device scanner with fingerprinting
# Category: nullsec/recon

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Value: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

LOOT_DIR="/mmc/nullsec/bluetooth"
mkdir -p "$LOOT_DIR"

PROMPT "СКАНЕР BLUETOOTH

Сканирование ближайших устройств Bluetooth
и BLE.

Функции:
- Обнаружение классического BT
- Сканирование рекламы BLE
- Отпечатки устройств
- Идентификация производителя
- Логирование силы сигнала

Нажмите OK для настройки."

# Check for Bluetooth tools
BT_TOOL=""
if command -v hcitool >/dev/null 2>&1; then
    BT_TOOL="hcitool"
elif command -v bluetoothctl >/dev/null 2>&1; then
    BT_TOOL="bluetoothctl"
else
    ERROR_DIALOG "Нет инструментов Bluetooth!

Установите hcitool или
bluetoothctl сначала.

opkg install bluez-utils"
    exit 1
fi

# Check adapter
if ! hciconfig hci0 up 2>/dev/null; then
    ERROR_DIALOG "Нет адаптера Bluetooth!

Убедитесь, что USB BT dongle
подключен."
    exit 1
fi

PROMPT "РЕЖИМ СКАНИРОВАНИЯ:

1. Классический Bluetooth
2. BLE (Низкое энергопотребление)
3. Оба BT + BLE
4. Непрерывный монитор

Используется: $BT_TOOL
Адаптер: hci0

Выберите режим далее."

SCAN_MODE=$(NUMBER_PICKER "Режим (1-4):" 3)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_MODE=3 ;; esac

DURATION=$(NUMBER_PICKER "Длительность сканирования (секунды):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac
[ $DURATION -lt 10 ] && DURATION=10
[ $DURATION -gt 600 ] && DURATION=600

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ СКАНИРОВАНИЕ BT?

Режим: $SCAN_MODE
Длительность: ${DURATION}с
Адаптер: hci0

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
REPORT="$LOOT_DIR/bt_scan_$TIMESTAMP.txt"
RAW_LOG="$LOOT_DIR/bt_raw_$TIMESTAMP.log"

LOG "Сканирование устройств Bluetooth..."
SPINNER_START "Сканирование Bluetooth..."

echo "=======================================" > "$REPORT"
echo "    BLUETOOTH-СКАНИРОВАНИЕ NULLSEC" >> "$REPORT"
echo "=======================================" >> "$REPORT"
echo "" >> "$REPORT"
echo "Scan Time: $(date)" >> "$REPORT"
echo "Длительность: ${DURATION}s" >> "$REPORT"
echo "Adapter: hci0" >> "$REPORT"
echo "" >> "$REPORT"

BT_COUNT=0
BLE_COUNT=0

# Classic Bluetooth scan
if [ "$SCAN_MODE" -eq 1 ] || [ "$SCAN_MODE" -eq 3 ]; then
    echo "--- КЛАССИЧЕСКИЕ BLUETOOTH-УСТРОЙСТВА ---" >> "$REPORT"
    echo "" >> "$REPORT"

    SCAN_TIMEOUT=$((DURATION / 2))
    [ "$SCAN_MODE" -eq 1 ] && SCAN_TIMEOUT=$DURATION

    timeout "$SCAN_TIMEOUT" hcitool scan --flush 2>/dev/null | while IFS=$'\t' read -r addr name; do
        [ -z "$addr" ] && continue
        [[ "$addr" == *"Scanning"* ]] && continue

        # Get device info
        CLASS=$(hcitool info "$addr" 2>/dev/null | grep "Device Class" | awk '{print $NF}')
        RSSI=$(hcitool rssi "$addr" 2>/dev/null | awk '{print $NF}')
        VENDOR=$(echo "$addr" | cut -d: -f1-3)

        echo "Device: $name" >> "$REPORT"
        echo "  MAC: $addr" >> "$REPORT"
        echo "  OUI: $VENDOR" >> "$REPORT"
        [ -n "$CLASS" ] && echo "  Class: $CLASS" >> "$REPORT"
        [ -n "$RSSI" ] && echo "  RSSI: ${RSSI}dBm" >> "$REPORT"
        echo "" >> "$REPORT"

        BT_COUNT=$((BT_COUNT + 1))
    done

    echo "Classic devices found: $BT_COUNT" >> "$REPORT"
    echo "" >> "$REPORT"
fi

# BLE scan
if [ "$SCAN_MODE" -eq 2 ] || [ "$SCAN_MODE" -eq 3 ]; then
    echo "--- BLE-УСТРОЙСТВА ---" >> "$REPORT"
    echo "" >> "$REPORT"

    BLE_TIMEOUT=$((DURATION / 2))
    [ "$SCAN_MODE" -eq 2 ] && BLE_TIMEOUT=$DURATION

    timeout "$BLE_TIMEOUT" hcitool lescan --duplicates 2>/dev/null > "$RAW_LOG" &
    BLE_PID=$!
    sleep "$BLE_TIMEOUT"
    kill $BLE_PID 2>/dev/null

    # Parse BLE results
    sort -u "$RAW_LOG" 2>/dev/null | while read -r addr name; do
        [ -z "$addr" ] && continue
        [[ "$addr" == *"Set"* ]] && continue
        [[ "$addr" == *"LE"* ]] && continue

        VENDOR=$(echo "$addr" | cut -d: -f1-3)
        echo "BLE: ${name:-(unknown)} | $addr | OUI:$VENDOR" >> "$REPORT"
        BLE_COUNT=$((BLE_COUNT + 1))
    done

    BLE_COUNT=$(sort -u "$RAW_LOG" 2>/dev/null | grep -cE "([0-9A-Fa-f]{2}:){5}" || echo 0)
    echo "" >> "$REPORT"
    echo "BLE devices found: $BLE_COUNT" >> "$REPORT"
    echo "" >> "$REPORT"
fi

# Continuous monitor mode
if [ "$SCAN_MODE" -eq 4 ]; then
    echo "--- НЕПРЕРЫВНЫЙ МОНИТОРИНГ ---" >> "$REPORT"
    echo "" >> "$REPORT"

    timeout "$DURATION" hcitool lescan --duplicates 2>/dev/null | \
        while read -r addr name; do
            [ -n "$addr" ] && echo "$(date '+%H:%M:%S') $addr $name" >> "$RAW_LOG"
        done &
    MON_PID=$!
    wait $MON_PID 2>/dev/null

    UNIQUE=$(sort -u "$RAW_LOG" 2>/dev/null | grep -cE "([0-9A-Fa-f]{2}:){5}" || echo 0)
    TOTAL=$(wc -l < "$RAW_LOG" 2>/dev/null | tr -d ' ')
    echo "Total advertisements: $TOTAL" >> "$REPORT"
    echo "Unique devices: $UNIQUE" >> "$REPORT"
fi

echo "" >> "$REPORT"
echo "=======================================" >> "$REPORT"

SPINNER_STOP

TOTAL_DEVICES=$((BT_COUNT + BLE_COUNT))
[ "$SCAN_MODE" -eq 4 ] && TOTAL_DEVICES=$(sort -u "$RAW_LOG" 2>/dev/null | grep -cE "([0-9A-Fa-f]{2}:){5}" || echo 0)

PROMPT "СКАНИРОВАНИЕ BLUETOOTH ЗАВЕРШЕНО

Классический BT: $BT_COUNT
Устройства BLE: $BLE_COUNT
Всего: $TOTAL_DEVICES

Отчет сохранен:
$REPORT

Нажмите OK для выхода."
