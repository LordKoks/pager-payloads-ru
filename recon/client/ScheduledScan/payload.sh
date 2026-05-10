#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Плановое сканирование
# Author: bad-antics
# Description: Автоматическое периодическое сканирование WiFi с сохранением результатов
# Category: nullsec

LOOT_DIR="/mmc/nullsec/scheduled"
mkdir -p "$LOOT_DIR"

PROMPT "ПЛАНОВОЕ СКАНИРОВАНИЕ
━━━━━━━━━━━━━━━━━━━━━━━━━
Автоматическое периодическое
сканирование WiFi с ведением журнала.

Идеально для обследования территории
и длительного мониторинга.

Нажми OK для настройки."

INTERVAL=$(NUMBER_PICKER "Интервал сканирования (мин):" 15)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=15 ;; esac
[ $INTERVAL -lt 1 ] && INTERVAL=1

TOTAL_SCANS=$(NUMBER_PICKER "Всего сканирований (0 = бесконечно):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TOTAL_SCANS=10 ;; esac

SCAN_DUR=$(NUMBER_PICKER "Длительность одного сканирования (сек):" 15)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_DUR=15 ;; esac
[ $SCAN_DUR -lt 5 ] && SCAN_DUR=5
[ $SCAN_DUR -gt 60 ] && SCAN_DUR=60

resp=$(CONFIRMATION_DIALOG "НАСТРОЙКИ РАСПИСАНИЯ:
━━━━━━━━━━━━━━━━━━━━━━━━━
Интервал: ${INTERVAL} мин
Сканирований: $([ $TOTAL_SCANS -eq 0 ] && echo "Бесконечно" || echo $TOTAL_SCANS)
Длительность: ${SCAN_DUR} сек

ЗАПУСТИТЬ?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Мониторный интерфейс не найден!"; exit 1; }

SCAN_NUM=0
MASTER_LOG="$LOOT_DIR/schedule_$(date +%Y%m%d_%H%M%S).csv"
echo "scan_num,timestamp,networks,clients" > "$MASTER_LOG"

while true; do
    SCAN_NUM=$((SCAN_NUM + 1))
    LOG "Запуск планового сканирования #$SCAN_NUM"
    
    rm -f /tmp/sched_scan*
    timeout $SCAN_DUR airodump-ng "$MONITOR_IF" -w /tmp/sched_scan --output-format csv 2>/dev/null &
    sleep $SCAN_DUR
    killall airodump-ng 2>/dev/null
    
    NET_COUNT=$(grep -c "^[0-9A-Fa-f]" /tmp/sched_scan-01.csv 2>/dev/null || echo "0")
    CLIENT_COUNT=$(awk '/Station MAC/,0' /tmp/sched_scan-01.csv 2>/dev/null | grep -c "^[0-9A-Fa-f]" || echo "0")
    
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$SCAN_NUM,$TIMESTAMP,$NET_COUNT,$CLIENT_COUNT" >> "$MASTER_LOG"
    
    cp /tmp/sched_scan-01.csv "$LOOT_DIR/scan_${SCAN_NUM}_$(date +%H%M%S).csv" 2>/dev/null
    
    [ $TOTAL_SCANS -ne 0 ] && [ $SCAN_NUM -ge $TOTAL_SCANS ] && break
    sleep $((INTERVAL * 60))
done

PROMPT "ПЛАНОВОЕ СКАНИРОВАНИЕ ЗАВЕРШЕНО
━━━━━━━━━━━━━━━━━━━━━━━━━
Выполнено сканирований: $SCAN_NUM
Основной журнал: $(basename $MASTER_LOG)
━━━━━━━━━━━━━━━━━━━━━━━━━
Все результаты сохранены в:
$LOOT_DIR"