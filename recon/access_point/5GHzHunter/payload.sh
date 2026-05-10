#!/bin/sh
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec 5GHz Spectrum Scanner
# Author: bad-antics
# Description: Сканирует диапазон 5 ГГц в поисках менее загруженных каналов

# FIX: Добавляем путь к airodump-ng из установленного пакета
export PATH=/mmc/usr/sbin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

LOOT_DIR="/mmc/nullsec/loot"
mkdir -p "$LOOT_DIR"

PROMPT "5 ГГц сканер для поиска чистых каналов (36-165). Нажмите OK для сканирования."

MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && ERROR_DIALOG "Интерфейс монитора не найден!" && exit 1

SPINNER_START "Сканирование диапазона 5 ГГц..."
rm -f /tmp/5ghz_scan*
# FIX: Убираем подавление ошибок, чтобы видеть проблемы в логе /tmp/airodump.log
timeout 25 airodump-ng "$MONITOR_IF" --band a -w /tmp/5ghz_scan --output-format csv > /tmp/airodump.log 2>&1 &
sleep 25
killall airodump-ng 2>/dev/null
SPINNER_STOP

# FIX: Проверяем, создался ли CSV-файл
CSV_FILE="/tmp/5ghz_scan-01.csv"
if [ ! -f "$CSV_FILE" ]; then
    ERROR_DIALOG "Ошибка: CSV файл не создан! Лог: /tmp/airodump.log"
    exit 1
fi

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
done < "$CSV_FILE"

echo -e "$RESULTS" > "$LOOT_DIR/5ghz_$(date +%Y%m%d_%H%M%S).txt"

PROMPT "Результаты сканирования 5 ГГц

Найдено сетей: $COUNT

$(echo -e "$RESULTS" | sort -t' ' -k2 -rn | head -8)

Сохранено в каталог логов."
