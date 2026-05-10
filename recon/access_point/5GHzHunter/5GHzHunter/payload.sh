#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec охотник 5 ГГц
# Author: bad-antics
# Description: Сканер диапазона 5 ГГц для поиска менее загруженных высокоскоростных целей
# Category: nullsec

LOOT_DIR="/mmc/nullsec/loot"
mkdir -p "$LOOT_DIR"

PROMPT "5ГГц ОХОТНИК
━━━━━━━━━━━━━━━━━━━━━━━━━
Сканирование диапазона 5 ГГц
для поиска высокоскоростных целей.

Каналы 36-165.

Нажмите ОК для сканирования."

MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && ERROR_DIALOG "Интерфейс монитора не найден!" && exit 1

SPINNER_START "Сканирование диапазона 5 ГГц..."
rm -f /tmp/5ghz_scan*
timeout 25 airodump-ng "$MONITOR_IF" --band a -w /tmp/5ghz_scan --output-format csv 2>/dev/null &
sleep 25
killall airodump-ng 2>/dev/null
SPINNER_STOP

COUNT=0
RESULTS=""
while IFS=',' read -r bssid x1 x2 channel x3 x4 x5 x6 power x7 x8 x9 x10 essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    channel=$(echo "$channel" | tr -d ' ')
    essid=$(echo "$essid" | tr -d ' ' | head -c 16)
    [ -z "$essid" ] && essid="[Hidden]"
    power=$(echo "$power" | tr -d ' ')
    COUNT=$((COUNT + 1))
    RESULTS="${RESULTS}CH${channel} ${power}dBm ${essid}\n"
done < /tmp/5ghz_scan-01.csv

echo -e "$RESULTS" > "$LOOT_DIR/5ghz_$(date +%Y%m%d_%H%M%S).txt"

PROMPT "РЕЗУЛЬТАТЫ 5ГГц
━━━━━━━━━━━━━━━━━━━━━━━━━
Найдено сетей: $COUNT

$(echo -e "$RESULTS" | sort -t' ' -k2 -rn | head -8)

Сохранено в каталог добычи."
