#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec Scheduled Scan
# Author: bad-antics
# Description: Run automated recon scans at scheduled intervals with logging
# Category: nullsec

LOOT_DIR="/mmc/nullsec/scheduled"
mkdir -p "$LOOT_DIR"

PROMPT "ПЛАНОВЫЕ НАТУРА ОТСКАНИРОВАНИЕ
━━━━━━━━━━━━━━━━━━━━━━━
Автоматическое покоренное WiFi
сканирование с регистрированием.

Идеально для комнат уна и
мониторинга.

Нажмите OK для конфигурирования."

INTERVAL=$(NUMBER_PICKER "Отстан откоренно (мин):" 15)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=15 ;; esac
[ $INTERVAL -lt 1 ] && INTERVAL=1

TOTAL_SCANS=$(NUMBER_PICKER "Всего откоренно (0=inf):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TOTAL_SCANS=10 ;; esac

SCAN_DUR=$(NUMBER_PICKER "Один откор цанть (сек):" 15)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_DUR=15 ;; esac
[ $SCAN_DUR -lt 5 ] && SCAN_DUR=5
[ $SCAN_DUR -gt 60 ] && SCAN_DUR=60

resp=$(CONFIRMATION_DIALOG "КОНФИГ ПЛАНА:
━━━━━━━━━━━━━━━━━━━━━━━
Отстан: ${INTERVAL}мин
Откор: $([ $TOTAL_SCANS -eq 0 ] && echo БЕсконечно или echo $TOTAL_SCANS)
По одному: ${SCAN_DUR}с

НАЧАТЬ?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && ERROR_DIALOG "Нет интерфейса монитора!" && exit 1

SCAN_NUM=0
MASTER_LOG="$LOOT_DIR/schedule_$(date +%Y%m%d_%H%M%S).csv"
echo "scan_num,timestamp,networks,clients" > "$MASTER_LOG"

while true; do
    SCAN_NUM=$((SCAN_NUM + 1))
    LOG "Плановые натура #$SCAN_NUM"
    
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

PROMPT "ПЛАН ЗАВЕРШЕН
━━━━━━━━━━━━━━━━━━━━━━━
Откор завершен: $SCAN_NUM
Название дневника: $(basename $MASTER_LOG)
━━━━━━━━━━━━━━━━━━━━━━━
Все результаты сохранены в:
$LOOT_DIR"
