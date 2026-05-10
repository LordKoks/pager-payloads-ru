#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Защита от Rogue USB
# Author: NullSec
# Description: Мониторит USB-порты и защищает Pineapple от несанкционированных USB-устройств
# Category: nullsec/blue-team

LOOT_DIR="/mmc/nullsec/usbguard"
mkdir -p "$LOOT_DIR"

PROMPT "ЗАЩИТА ОТ ROGUE USB

Мониторит USB-порты на 
подключение несанкционированных устройств.

Защищает твой Pineapple от USB-атак:
- BadUSB / Rubber Ducky
- Неизвестные флешки
- Rogue сетевые адаптеры
- Кейлоггеры
- USB-импланты

При подключении любого 
неразрешённого устройства — 
выдаёт тревогу.

Нажми OK для настройки."

TIMESTAMP=$(date +%Y%m%d_%H%M)
ALERT_LOG="$LOOT_DIR/usb_alerts_$TIMESTAMP.log"
WHITELIST="$LOOT_DIR/whitelist.conf"
DEVICE_LOG="$LOOT_DIR/device_history.log"

echo "[$(date)] Защита от Rogue USB запущена" > "$ALERT_LOG"

# Создание начального белого списка
build_whitelist() {
    echo "# NullSec RogueUSBGuard — Белый список" > "$WHITELIST.tmp"
    echo "# Создан: $(date)" >> "$WHITELIST.tmp"
    echo "# Формат: VID:PID|Производитель|Продукт|Серийный номер" >> "$WHITELIST.tmp"
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

# Проверка, находится ли устройство в белом списке
is_whitelisted() {
    local vid="$1" pid="$2"
    grep -q "^${vid}:${pid}|" "$WHITELIST" 2>/dev/null
    return $?
}

# Получение описания класса устройства
get_device_class() {
    local class="$1"
    case "$class" in
        "00") echo "Составное устройство" ;;
        "01") echo "Аудио" ;;
        "02") echo "CDC/Модем" ;;
        "03") echo "HID (Клавиатура/Мышь)" ;;
        "05") echo "Физический интерфейс" ;;
        "06") echo "Изображение" ;;
        "07") echo "Принтер" ;;
        "08") echo "Накопитель" ;;
        "09") echo "Хаб" ;;
        "0a") echo "CDC-Data" ;;
        "0b") echo "Смарт-карта" ;;
        "0e") echo "Видео" ;;
        "0f") echo "Медицина" ;;
        "e0") echo "Беспроводное (Bluetooth/WiFi)" ;;
        "ef") echo "Разное" ;;
        "fe") echo "Специфическое приложение" ;;
        "ff") echo "Специфическое для производителя" ;;
        *)    echo "Неизвестно ($class)" ;;
    esac
}

# Оценка уровня угрозы
assess_threat() {
    local class="$1" prod="$2"
    local threat="LOW"
    local reason=""

    # HID-устройства — самая высокая угроза (BadUSB, Rubber Ducky)
    if [ "$class" = "03" ]; then
        threat="КРИТИЧЕСКИЙ"
        reason="HID-устройство — возможна атака BadUSB / keystroke injection"
    elif [ "$class" = "02" ]; then
        threat="ВЫСОКИЙ"
        reason="CDC-устройство — возможен сетевой имплант или эксплойт"
    elif [ "$class" = "e0" ]; then
        threat="СРЕДНИЙ"
        reason="Беспроводной адаптер — требуется проверка"
    elif [ "$class" = "08" ]; then
        threat="СРЕДНИЙ"
        reason="Накопитель — возможны вредоносные автозапуски"
    elif [ "$class" = "00" ]; then
        threat="ВЫСОКИЙ"
        reason="Составное устройство — может скрывать HID-интерфейс"
    fi

    # Проверка на известные инструменты атак
    prod_lower=$(echo "$prod" | tr '[:upper:]' '[:lower:]')
    case "$prod_lower" in
        *"rubber"*|*"ducky"*|*"bashbunny"*|*"lanturtle"*)
            threat="КРИТИЧЕСКИЙ"
            reason="Обнаружен известный инструмент атаки: $prod"
            ;;
        *"teensy"*|*"arduino"*|*"digispark"*)
            threat="ВЫСОКИЙ"
            reason="Программируемое USB-устройство: $prod"
            ;;
        *"omg"*|*"cable"*|*"implant"*)
            threat="КРИТИЧЕСКИЙ"
            reason="Возможный USB-имплант: $prod"
            ;;
    esac

    echo "${threat}|${reason}"
}

# Снимок текущего состояния USB
snapshot_usb() {
    for dev in /sys/bus/usb/devices/[0-9]*; do
        [ ! -f "$dev/idVendor" ] && continue
        VID=$(cat "$dev/idVendor" 2>/dev/null)
        PID=$(cat "$dev/idProduct" 2>/dev/null)
        echo "${VID}:${PID}"
    done | sort
}

# Выбор режима работы
PROMPT "ВЫБЕРИ РЕЖИМ РАБОТЫ:

1. Обучение + Защита
   (добавить текущие USB-устройства 
    в белый список и следить за новыми)

2. Параноидальный режим
   (тревога при ЛЮБОМ USB-событии)

3. Только аудит
   (только логирование, без тревог)

Выбери режим:"

MODE=$(NUMBER_PICKER "Режим (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MODE=1 ;; esac
[ $MODE -lt 1 ] && MODE=1
[ $MODE -gt 3 ] && MODE=3

DURATION=$(NUMBER_PICKER "Длительность защиты (минуты):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac
[ $DURATION -lt 1 ] && DURATION=1
[ $DURATION -gt 1440 ] && DURATION=1440

if [ $MODE -eq 1 ]; then
    build_whitelist
    mv "$WHITELIST.tmp" "$WHITELIST"
    WL_COUNT=$(grep -cv "^#" "$WHITELIST" 2>/dev/null || echo 0)

    resp=$(CONFIRMATION_DIALOG "РЕЖИМ: ОБУЧЕНИЕ + ЗАЩИТА

В белый список добавлено $WL_COUNT устройств.

Время защиты: ${DURATION} мин

Любое новое USB-устройство 
вызовет тревогу.

Запустить защиту?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

elif [ $MODE -eq 2 ]; then
    resp=$(CONFIRMATION_DIALOG "ПАРАНОИДАЛЬНЫЙ РЕЖИМ

Время защиты: ${DURATION} мин

Тревога будет при ЛЮБОМ 
подключении или отключении USB.

Белый список не используется.

Запустить?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

elif [ $MODE -eq 3 ]; then
    resp=$(CONFIRMATION_DIALOG "РЕЖИМ АУДИТА

Длительность: ${DURATION} мин

Будет только вести журнал 
всех USB-событий.

Тревоги отключены.

Запустить?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0
fi

# Начальный снимок
PREV_SNAPSHOT=$(snapshot_usb)
END_TIME=$(($(date +%s) + DURATION * 60))
ALERT_COUNT=0
EVENT_COUNT=0

SPINNER_START "Защита от Rogue USB активна..."

MODE_NAMES=("" "Обучение + Защита" "Параноидальный" "Аудит")

while [ $(date +%s) -lt $END_TIME ]; do
    CURRENT_SNAPSHOT=$(snapshot_usb)

    # Новые устройства
    NEW_DEVICES=$(comm -13 <(echo "$PREV_SNAPSHOT") <(echo "$CURRENT_SNAPSHOT") 2>/dev/null)

    # Отключённые устройства
    REMOVED_DEVICES=$(comm -23 <(echo "$PREV_SNAPSHOT") <(echo "$CURRENT_SNAPSHOT") 2>/dev/null)

    # Обработка новых устройств
    if [ -n "$NEW_DEVICES" ]; then
        while read -r vidpid; do
            [ -z "$vidpid" ] && continue
            VID=$(echo "$vidpid" | cut -d: -f1)
            PID=$(echo "$vidpid" | cut -d: -f2)
            EVENT_COUNT=$((EVENT_COUNT + 1))

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

            echo "[$NOW] ПОДКЛЮЧЕНО: $VID:$PID | $MFG | $PROD | Класс:$CLASS_NAME | Serial:$SERIAL | Уровень:$THREAT_LEVEL | $THREAT_REASON" >> "$ALERT_LOG"
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

                PROMPT "⚠ USB ТРЕВОГА #$ALERT_COUNT

ПОДКЛЮЧЕНО НОВОЕ УСТРОЙСТВО!

Производитель: $MFG
Устройство:    $PROD
ID:            $VID:$PID
Класс:         $CLASS_NAME
Серийный №:    $SERIAL

УРОВЕНЬ УГРОЗЫ: $THREAT_LEVEL
$THREAT_REASON

Нажми OK для продолжения мониторинга."

                SPINNER_START "Защита от Rogue USB активна..."
            fi
        done <<< "$NEW_DEVICES"
    fi

    # Обработка отключённых устройств
    if [ -n "$REMOVED_DEVICES" ]; then
        while read -r vidpid; do
            [ -z "$vidpid" ] && continue
            EVENT_COUNT=$((EVENT_COUNT + 1))
            NOW=$(date '+%Y-%m-%d %H:%M:%S')
            echo "[$NOW] ОТКЛЮЧЕНО: $vidpid" >> "$ALERT_LOG"
            echo "[$NOW] REMOVE $vidpid" >> "$DEVICE_LOG"

            if [ $MODE -eq 2 ]; then
                ALERT_COUNT=$((ALERT_COUNT + 1))
                SPINNER_STOP
                PROMPT "USB УСТРОЙСТВО ОТКЛЮЧЕНО

Устройство $vidpid
было отключено.

Время: $NOW

Нажми OK для продолжения."
                SPINNER_START "Защита от Rogue USB активна..."
            fi
        done <<< "$REMOVED_DEVICES"
    fi

    PREV_SNAPSHOT="$CURRENT_SNAPSHOT"
    sleep 2
done

SPINNER_STOP

CURRENT_COUNT=$(snapshot_usb | wc -l)

PROMPT "ЗАЩИТА ОТ ROGUE USB ЗАВЕРШЕНА

Режим: ${MODE_NAMES[$MODE]}
Длительность: ${DURATION} мин

Событий: $EVENT_COUNT
Тревог: $ALERT_COUNT
Текущих устройств: $CURRENT_COUNT

Нажми OK для деталей."

PROMPT "СОХРАНЁННЫЕ ФАЙЛЫ

Журнал тревог:
usb_alerts_$TIMESTAMP.log

История устройств:
device_history.log

Белый список:
whitelist.conf

Папка: $LOOT_DIR/

Нажми OK для выхода."