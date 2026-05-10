#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Обнаруживатель Rogue
# Author: bad-antics
# Description: Охота за rogue AP, evil twin и бъсания унавторизованных SSID в WiFi окружении
# Category: nullsec/blue-team

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ОБНАРУЖИВАТЕЛЬ ROGUE AP

Сканирует неавторизованные
точки доступа:

- Обнаружение evil twin
- Проверка дубликатных SSID
- Открытые AP вульнерабилитеты
- Оповещение неизвестных BSSID

Сканирование: 45 секунд

Нажмите ОК для охоты."

OUTDIR="/mmc/nullsec/blue-team/rogue-detector"
mkdir -p "$OUTDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS="$OUTDIR/rogue_${TIMESTAMP}.txt"
KNOWN="$OUTDIR/known_aps.csv"

# Init whitelist
if [ ! -f "$KNOWN" ]; then
    echo "# Known APs — add authorized BSSIDs" > "$KNOWN"
    echo "# BSSID,ESSID" >> "$KNOWN"
fi

SPINNER_START "Сканирую rogue AP (45s)..."
timeout 45 airodump-ng $IFACE -w /tmp/rogue --output-format csv 2>/dev/null
SPINNER_STOP

CSV="/tmp/rogue-01.csv"
[ ! -f "$CSV" ] && { ERROR_DIALOG "Нет данных скана!"; exit 1; }

SPINNER_START "Анализирую rogue..."

grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | \
    awk -F',' '{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$14); print $1","$14}' > /tmp/rogue_all.csv
TOTAL=$(wc -l < /tmp/rogue_all.csv)

# Evil twin detection
DUPES=$(awk -F',' '{gsub(/^ +| +$/,"",$2); if(length($2)>0) print $2}' /tmp/rogue_all.csv | sort | uniq -d)
TWIN_COUNT=$(echo "$DUPES" | grep -c "." 2>/dev/null || echo 0)

# Open networks
OPEN_COUNT=$(grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | grep -ci "OPN" || echo 0)

{
    echo "╠══════════════════════════════════════╪"
    echo "║  Отчет обнаружения Rogue AP    ║"
    echo "╞══════════════════════════════════════╠"
    echo ""
    echo "Сканирование: $(date)"
    echo "Всего AP: $TOTAL"
    echo ""
    echo "── Проверка Evil Twin ───────────────"
    if [ "$TWIN_COUNT" -gt 0 ]; then
        echo "⚠️ $TWIN_COUNT ESSID(ы) с несколъкими BSSID!"
        echo "$DUPES" | while read ESSID; do
            [ -n "$ESSID" ] && echo "  $ESSID:" && grep ",$ESSID$" /tmp/rogue_all.csv | awk -F',' '{print "    "$1}'
        done
    else
        echo "✅ Нет pattern evil twin"
    fi
    echo ""
    echo "── Открытые сети ───────────────"
    if [ "$OPEN_COUNT" -gt 0 ]; then
        echo "⚠️ $OPEN_COUNT открытые сети"
        grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | grep -i "OPN" | \
            awk -F',' '{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$14); printf "  %s  %s\n", $1, $14}'
    else
        echo "✅ Нет открытых сетей"
    fi
    echo ""
    echo "── Все AP ────────────────────"
    grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | \
        awk -F',' '{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$4); gsub(/^ +| +$/,"",$6); gsub(/^ +| +$/,"",$9); gsub(/^ +| +$/,"",$14); printf "%-18s CH:%-3s PWR:%-5s %-10s %s\n", $1, $4, $9, $6, $14}'
} > "$RESULTS"

SPINNER_STOP

rm -f /tmp/rogue* /tmp/rogue_all.csv 2>/dev/null

ALERTS=$((TWIN_COUNT + OPEN_COUNT))
if [ "$ALERTS" -gt 0 ]; then
    CONFIRMATION_DIALOG "⚠️ Найдены Rogue AP!

Всего AP: $TOTAL
Evil Twin: $TWIN_COUNT
Открытые AP: $OPEN_COUNT

Отчет: $RESULTS"
else
    CONFIRMATION_DIALOG "✅ Rogue не обнаружены

Всего AP: $TOTAL
Окружение чисто.

Отчет: $RESULTS"
fi
