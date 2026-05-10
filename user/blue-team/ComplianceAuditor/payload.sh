#!/bin/bash
# Title: Compliance Auditor
# Author: bad-antics
# Description: Audits WiFi networks against security best practices — WPA3, WEP, open networks, WPS
# Category: nullsec/blue-team

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "Одитор КОМПЛАЙЕНСИ

Одит политики WiFi безопасности.

Проверяет:
- WEP (неработающее шифрование)
- Открытые сети (без аутентификации)
- Трибуннеми WPA3
- Скрытые SSID

Откор: 30 секунд

Нажмите OK для аудита."

OUTDIR="/mmc/nullsec/blue-team/compliance"
mkdir -p "$OUTDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$OUTDIR/audit_${TIMESTAMP}.txt"

SPINNER_START "Рафарирование всех каналов (30с)..."
timeout 30 airodump-ng $IFACE -w /tmp/compliance --output-format csv 2>/dev/null
SPINNER_STOP

CSV="/tmp/compliance-01.csv"
[ ! -f "$CSV" ] && { ERROR_DIALOG "На сканированных данных!"; exit 1; }

SPINNER_START "Анализ соответствия..."

TOTAL=$(grep -cE "^([0-9A-Fa-f]{2}:){5}" "$CSV" 2>/dev/null || echo 0)
WPA3=$(grep -ci "WPA3" "$CSV" 2>/dev/null || echo 0)
WPA2=$(grep -i "WPA2" "$CSV" 2>/dev/null | grep -cvi "WPA3" || echo 0)
WEP=$(grep -ci "WEP" "$CSV" 2>/dev/null || echo 0)
OPEN=$(grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" 2>/dev/null | grep -cE ",\s*OPN\s*," || echo 0)
HIDDEN=$(grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" 2>/dev/null | awk -F',' '{gsub(/^ +| +$/,"",$14); if(length($14)<1) c++} END{print c+0}')
FAILS=$((WEP + OPEN))

{
    echo "╔═══════════════════════════════════════╗"
    echo "║  NullSec Compliance Audit Report      ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Date: $(date)"
    echo ""
    echo "── Отсути ───────────────"
    echo "Всего сетей:      $TOTAL"
    echo "WPA3 (сильнейш):   $WPA3"
    echo "WPA2 (стандарт):   $WPA2"
    echo "WEP (неработающ):   $WEP"
    echo "Открытые (нет аут): $OPEN"
    echo "Скрытые SSID:      $HIDDEN"
    echo ""
    echo "── Находки ───────────────"
    [ "$WEP" -gt 0 ] && echo "⚠ НОПАВКА: $WEP WEP сетей"
    [ "$OPEN" -gt 0 ] && echo "⚠ НОПАВКА: $OPEN открытых сетей"
    [ "$WPA3" -eq 0 ] && [ "$TOTAL" -gt 0 ] && echo "⚠ ПРЕДОПОВЕЖДЕНИЕ: Нет WPA3"
    [ "$HIDDEN" -gt 0 ] && echo "ℹ️  ИНФО: $HIDDEN скрытых сетей"
    [ "$FAILS" -eq 0 ] && echo "✅ ОК: Нет критических ошибок"
    echo ""
    echo "── Опись сетей ──────────"
    grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | sort -t',' -k9 -n -r | \
        awk -F',' '{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$4); gsub(/^ +| +$/,"",$6); gsub(/^ +| +$/,"",$9); gsub(/^ +| +$/,"",$14); printf "%-18s CH:%-3s PWR:%-5s %-12s %s\n", $1, $4, $9, $6, $14}'
} > "$REPORT"

SPINNER_STOP

rm -f /tmp/compliance* 2>/dev/null

if [ "$FAILS" -gt 0 ]; then
    CONFIRMATION_DIALOG "⛔ Compliance FAILED\n\nСетьs: $TOTAL\nFailures: $FAILS\n- WEP: $WEP\n- Open: $OPEN\n\nReport: $REPORT"
else
    CONFIRMATION_DIALOG "✅ Compliance PASSED\n\nСетьs: $TOTAL\nWPA3: $WPA3\nWPA2: $WPA2\n\nReport: $REPORT"
fi
