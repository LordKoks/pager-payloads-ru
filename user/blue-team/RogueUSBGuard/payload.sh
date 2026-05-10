#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Rogue USB Guard
# Author: NullSec
# Description: Monitors USB ports for unauthorized device insertions — defends the Pineapple itself
# Category: nullsec/blue-team

LOOT_DIR="/mmc/nullsec/usbguard"
mkdir -p "$LOOT_DIR"

PROMPT "ЖЕНДЕРНАО ROGUE USB

Наблюдает порты USB для 
неавторизованных устройств.

Защищает ВАШ Pineapple
от USB-атак:
- BadUSB / Rubber Ducky
- Неизвестные флешки
- Rogue-адаптеры
- Кейлоггеры
- USB-импланты

Овещают со внедрением
любого неутвержденного устройства.

Нажмите OK для настройки."

TIMESTAMP=$(date +%Y%m%d_%H%M)
ALERT_LOG="$LOOT_DIR/usb_alerts_$TIMESTAMP.log"
WHITELIST="$LOOT_DIR/whitelist.conf"
DEVICE_LOG="$LOOT_DIR/device_history.log"

echo "[жендерная $(date)] Начала работа RogueUSBGuard" > "$ALERT_LOG"

# Составление белого списка текущих устройств
build_whitelist() {
    echo "# NullSec RogueUSBGuard Одобренные устройства" > "$WHITELIST.tmp"
    echo "# Генерировано: $(date)" >> "$WHITELIST.tmp"
    echo "# Формат: VID:PID|Производитель|Тип" >> "$WHITELIST.tmp"
    echo "#" >> "$WHITELIST.tmp"

    for dev in /sys/bus/usb/devices/[0-9]*; do
        [ ! -f "$dev/idVendor" ] && continue
        VID=$(cat "$dev/idVendor" 2>/dev/null)
        PID=$(cat "$dev/idProduct" 2>/dev/null)
        MFG=$(cat "$dev/manufacturer" 2>/dev/null || echo "unknown")
        PROD=$(cat "$dev/product" 2>/dev/null || echo "unknown")
        SERIAL=$(cat "$dev/serial" 2>/dev/null || echo "none")
        echo "${VID}:${PID}|${MFG}|${PROD}|${SERIAL}" >> "$WHITELIST.tmp"
    done
}

# Проверка в белом списке
is_whitelisted() {
    local vid="$1" pid="$2"
    grep -q "^${vid}:${pid}|" "$WHITELIST" 2>/dev/null
    return $?
}

# Название класса устройства
get_device_class() {
    local class="$1"
    case "$class" in
        "00") echo "Композит" ;;
        "01") echo "Аудио" ;;
        "02") echo "CDC/Модем" ;;
        "03") echo "HID (клавиатура/мышь)" ;;
        "05") echo "Физический" ;;
        "06") echo "Контент" ;;
        "07") echo "Принтер" ;;
        "08") echo "Носитель" ;;
        "09") echo "Пиц" ;;
        "0a") echo "CDC-Данные" ;;
        "0b") echo "Смарт-Карта" ;;
        "0e") echo "Видео" ;;
        "0f") echo "Медицина" ;;
        "e0") echo "Беспроводное (BT/WiFi)" ;;
        "ef") echo "Мисц" ;;
        "fe") echo "Внедренные" ;;
        "ff") echo "Проприетарные" ;;
        *)    echo "Неизвестные ($class)" ;;
    esac
}

# Assess threat level
assess_threat() {
    local class="$1" prod="$2"
    local threat="LOW"
    local reason=""

    # HID devices are highest threat (BadUSB, Rubber Ducky)
    if [ "$class" = "03" ]; then
        threat="CRITICAL"
        reason="HID device — possible BadUSB/keystroke injection"
    # CDC can be used for network implants
    elif [ "$class" = "02" ]; then
        threat="HIGH"
        reason="CDC device — possible network implant or serial exploit"
    # Wireless adapters could be rogue
    elif [ "$class" = "e0" ]; then
        threat="MEDIUM"
        reason="Wireless adapter — verify it's authorized"
    # Mass Хранилище could contain autorun payloads
    elif [ "$class" = "08" ]; then
        threat="MEDIUM"
        reason="Хранилище device — check for malicious payloads"
    # Composite devices can hide HID behind other classes
    elif [ "$class" = "00" ]; then
        threat="HIGH"
        reason="Composite device — may contain hidden HID interface"
    fi

    # Check for known attack tool signatures
    prod_lower=$(echo "$prod" | tr '[:upper:]' '[:lower:]')
    case "$prod_lower" in
        *"rubber"*|*"ducky"*|*"bashbunny"*|*"lanturtle"*)
            threat="CRITICAL"
            reason="Known attack tool detected: $prod"
            ;;
        *"teensy"*|*"arduino"*|*"digispark"*)
            threat="HIGH"
            reason="Programmable USB device: $prod"
            ;;
        *"omg"*|*"cable"*|*"implant"*)
            threat="CRITICAL"
            reason="Possible USB implant: $prod"
            ;;
    esac

    echo "${threat}|${reason}"
}

# Snapshot current USB state
snapshot_usb() {
    for dev in /sys/bus/usb/devices/[0-9]*; do
        [ ! -f "$dev/idVendor" ] && continue
        VID=$(cat "$dev/idVendor" 2>/dev/null)
        PID=$(cat "$dev/idProduct" 2>/dev/null)
        echo "${VID}:${PID}"
    done | sort
}

# Choose mode
PROMPT "ВЫБЕРИТЕ РЕЖИМ:

1. Учить & Оставыль
   (добавить тек устр-ва)

2. ПАРАНОЙДНЫЙ
   (овещать у USB событие)

3. ТОЛЬКО АУДИТ
   (конк все USB, без на)

Выберите режим (1-3)."

MODE=$(NUMBER_PICKER "Mode (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MODE=1 ;; esac
[ $MODE -lt 1 ] && MODE=1
[ $MODE -gt 3 ] && MODE=3

DURATION=$(NUMBER_PICKER "Guard duration (min):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac
[ $DURATION -lt 1 ] && DURATION=1
[ $DURATION -gt 1440 ] && DURATION=1440

if [ $MODE -eq 1 ]; then
    # Build whitelist from current devices
    build_whitelist
    mv "$WHITELIST.tmp" "$WHITELIST"
    WL_COUNT=$(grep -cv "^#" "$WHITELIST" 2>/dev/null || echo 0)

    resp=$(CONFIRMATION_DIALOG "LEARN & GUARD

Whitelisted $WL_COUNT
current USB devices.

Guard for: ${DURATION}m

Any new USB device will
trigger an alert.

Start guarding?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

elif [ $MODE -eq 2 ]; then
    resp=$(CONFIRMATION_DIALOG "PARANOID MODE

Guard for: ${DURATION}m

ANY USB insertion or
removal will trigger
an immediate alert.

No whitelist — everything
is suspicious.

Start guarding?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

elif [ $MODE -eq 3 ]; then
    resp=$(CONFIRMATION_DIALOG "AUDIT MODE

Длительность: ${DURATION}m

Will silently log all
USB device activity.

No alerts — just logging.

Start audit?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0
fi

# Take initial snapshot
PREV_SNAPSHOT=$(snapshot_usb)
END_TIME=$(($(date +%s) + DURATION * 60))
ALERT_COUNT=0
EVENT_COUNT=0

SPINNER_START "USB Guard active..."

MODE_NAMES=("" "Learn & Guard" "Paranoid" "Audit")

while [ $(date +%s) -lt $END_TIME ]; do
    CURRENT_SNAPSHOT=$(snapshot_usb)

    # Find new devices (in current but not in previous)
    NEW_DEVICES=$(comm -13 <(echo "$PREV_SNAPSHOT") <(echo "$CURRENT_SNAPSHOT") 2>/dev/null)

    # Find removed devices
    REMOVED_DEVICES=$(comm -23 <(echo "$PREV_SNAPSHOT") <(echo "$CURRENT_SNAPSHOT") 2>/dev/null)

    # Process new devices
    if [ -n "$NEW_DEVICES" ]; then
        while read -r vidpid; do
            [ -z "$vidpid" ] && continue
            VID=$(echo "$vidpid" | cut -d: -f1)
            PID=$(echo "$vidpid" | cut -d: -f2)
            EVENT_COUNT=$((EVENT_COUNT + 1))

            # Find the sysfs device for details
            MFG="unknown"; PROD="unknown"; SERIAL="none"; CLASS="ff"
            for dev in /sys/bus/usb/devices/[0-9]*; do
                dv=$(cat "$dev/idVendor" 2>/dev/null)
                dp=$(cat "$dev/idProduct" 2>/dev/null)
                if [ "$dv" = "$VID" ] && [ "$dp" = "$PID" ]; then
                    MFG=$(cat "$dev/manufacturer" 2>/dev/null || echo "unknown")
                    PROD=$(cat "$dev/product" 2>/dev/null || echo "unknown")
                    SERIAL=$(cat "$dev/serial" 2>/dev/null || echo "none")
                    CLASS=$(cat "$dev/bDeviceClass" 2>/dev/null || echo "ff")
                    break
                fi
            done

            CLASS_NAME=$(get_device_class "$CLASS")
            THREAT_INFO=$(assess_threat "$CLASS" "$PROD")
            THREAT_LEVEL=$(echo "$THREAT_INFO" | cut -d'|' -f1)
            THREAT_REASON=$(echo "$THREAT_INFO" | cut -d'|' -f2)

            NOW=$(date '+%Y-%m-%d %H:%M:%S')

            # Log the event
            echo "[$NOW] INSERTED: $VID:$PID | $MFG | $PROD | Class:$CLASS_NAME | Serial:$SERIAL | Threat:$THREAT_LEVEL | $THREAT_REASON" >> "$ALERT_LOG"
            echo "[$NOW] INSERT $VID:$PID $PROD ($CLASS_NAME) [$THREAT_LEVEL]" >> "$DEVICE_LOG"

            SHOULD_ALERT=0
            if [ $MODE -eq 2 ]; then
                SHOULD_ALERT=1
            elif [ $MODE -eq 1 ]; then
                if ! is_whitelisted "$VID" "$PID"; then
                    SHOULD_ALERT=1
                fi
            fi

            if [ $SHOULD_ALERT -eq 1 ]; then
                ALERT_COUNT=$((ALERT_COUNT + 1))
                SPINNER_STOP

                PROMPT "⚠ USB ALERT #$ALERT_COUNT

DEVICE INSERTED!

Vendor:  $MFG
Product: $PROD
ID:      $VID:$PID
Class:   $CLASS_NAME
Serial:  $SERIAL

THREAT: $THREAT_LEVEL
$THREAT_REASON

Press OK to continue
monitoring."

                SPINNER_START "USB Guard active..."
            fi
        done <<< "$NEW_DEVICES"
    fi

    # Process removed devices
    if [ -n "$REMOVED_DEVICES" ]; then
        while read -r vidpid; do
            [ -z "$vidpid" ] && continue
            EVENT_COUNT=$((EVENT_COUNT + 1))
            NOW=$(date '+%Y-%m-%d %H:%M:%S')
            echo "[$NOW] REMOVED: $vidpid" >> "$ALERT_LOG"
            echo "[$NOW] REMOVE $vidpid" >> "$DEVICE_LOG"

            if [ $MODE -eq 2 ]; then
                ALERT_COUNT=$((ALERT_COUNT + 1))
                SPINNER_STOP
                PROMPT "USB REMOVED

Device $vidpid
was disconnected.

Time: $NOW

Press OK to continue."
                SPINNER_START "USB Guard active..."
            fi
        done <<< "$REMOVED_DEVICES"
    fi

    PREV_SNAPSHOT="$CURRENT_SNAPSHOT"
    sleep 2
done

SPINNER_STOP

# Summary
CURRENT_COUNT=$(snapshot_usb | wc -l)

PROMPT "USB GUARD COMPLETE

Режим: ${MODE_NAMES[$MODE]}
Длительность: ${DURATION}m

Events: $EVENT_COUNT
Тревоги: $ALERT_COUNT
Current devices: $CURRENT_COUNT

Press OK for details."

PROMPT "FILES SAVED

Alert log:
usb_alerts_$TIMESTAMP.log

Device history:
device_history.log

Whitelist:
whitelist.conf

Location: $LOOT_DIR/

Press OK to exit."
