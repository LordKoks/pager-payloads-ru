#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Охотник на Probe NullSec
# Author: bad-antics
# Description: Пассивный сбор probe-запросов для открытия скрытых сетей
# Category: nullsec

LOOT_DIR="/mmc/nullsec"
mkdir -p "$LOOT_DIR"/{probes,logs}

PROMPT "ОХОТНИК НА PROBE NULLSEC

Пассивный сбор probe-запросов
для открытия скрытых сетей
и предпочитаемых SSID клиентов.

100% пассивно - без передачи!

Нажмите ОК для настройки."

# Find monitor interface
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done

[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Интерфейс мониторинга не найден!"; exit 1; }

# Длительность
DURATION=$(NUMBER_PICKER "Длительность захвата (сек):" 120)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=120 ;; esac
[ $DURATION -lt 30 ] && DURATION=30
[ $DURATION -gt 600 ] && DURATION=600

# Переключение канала?
resp=$(CONFIRMATION_DIALOG "Включить переключение канала?

ДА = сканировать все каналы
НЕТ = остаться на текущем канале")
[ "$resp" = "$DUCKYSCRIPT_USER_CONFIRMED" ] && HOP="1"

resp=$(CONFIRMATION_DIALOG "Запустить захват probe?

Интерфейс: $MONITOR_IF
Длительность: ${DURATION}s
Переключение канала: $([ -n "$HOP" ] && echo ДА || echo НЕТ)")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# Захват
LOG "Запуск захвата probe..."
OUTFILE="$LOOT_DIR/probes/probes_$(date +%Y%m%d_%H%M%S).txt"

if [ -n "$HOP" ]; then
    # Channel hopping with airodump
    timeout $DURATION airodump-ng "$MONITOR_IF" -w /tmp/probe_cap --output-format csv 2>/dev/null &
    sleep $DURATION
    killall airodump-ng 2>/dev/null
    
    # Extract probes from CSV
    grep "Probe" /tmp/probe_cap*.csv 2>/dev/null | \
        awk -F',' '{print $1","$6}' | sort -u > "$OUTFILE"
else
    # Direct tcpdump capture
    timeout $DURATION tcpdump -i "$MONITOR_IF" -e -s 256 type mgt subtype probe-req 2>/dev/null | \
        grep -oE "SA:[0-9a-fA-F:]+|Probe Request \([^)]+\)" | \
        paste - - | sort -u > "$OUTFILE"
fi

# Результаты
PROBE_COUNT=$(wc -l < "$OUTFILE" 2>/dev/null || echo 0)
UNIQUE_SSIDS=$(grep -oE "Probe Request \([^)]+\)" "$OUTFILE" 2>/dev/null | sort -u | wc -l || echo 0)

PROMPT "ЗАХВАТ PROBE ЗАВЕРШЕН

Произведено probe: $PROBE_COUNT
Уникальных SSID: $UNIQUE_SSIDS

Сохранено в:
$OUTFILE

Нажмите ОК для выхода."
