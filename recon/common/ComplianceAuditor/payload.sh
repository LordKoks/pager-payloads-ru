#!/bin/bash
# Title: Compliance Auditor
# Author: bad-antics
# Description: Audits WiFi networks against security best practices — WPA3, WEP, open networks, WPS
# Category: nullsec/blue-team

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "АУДИТ СООТВЕТСТВИЯ

Проверка безопасности Wi-Fi сетей.

Проверяет:
- WEP (ломкое шифрование)
- Открытые сети (без авторизации)
- Поддержку WPA3
- Скрытые SSID

Сканирование: 30 секунд

Нажмите ОК для начала."

OUTDIR="/mmc/nullsec/blue-team/compliance"
mkdir -p "$OUTDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$OUTDIR/audit_${TIMESTAMP}.txt"

SPINNER_START "Сканирование всех каналов (30с)..."
timeout 30 airodump-ng $IFACE -w /tmp/compliance --output-format csv 2>/dev/null
SPINNER_STOP

CSV="/tmp/compliance-01.csv"
[ ! -f "$CSV" ] && { ERROR_DIALOG "Данные сканирования не получены!"; exit 1; }

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
    echo "║       Отчет аудита соответствия       ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Дата: $(date)"
    echo ""
    echo "── Итоги ───────────────────────────────"
    echo "Всего сетей:      $TOTAL"
    echo "WPA3 (надежные):  $WPA3"
    echo "WPA2 (стандарт):  $WPA2"
    echo "WEP (ломкие):     $WEP"
    echo "Открытые:         $OPEN"
    echo "Скрытые SSID:     $HIDDEN"
    echo ""
    echo "── Выводы ─────────────────────────────"
    [ "$WEP" -gt 0 ] && echo "⛔ ОШИБКА: $WEP WEP сеть(ей)"
    [ "$OPEN" -gt 0 ] && echo "⛔ ОШИБКА: $OPEN открытая сеть(и)"
    [ "$WPA3" -eq 0 ] && [ "$TOTAL" -gt 0 ] && echo "⚠️  ПРЕДУПРЕЖДЕНИЕ: WPA3 не обнаружен"
    [ "$HIDDEN" -gt 0 ] && echo "ℹ️  ИНФО: $HIDDEN скрытые сеть(и)"
    [ "$FAILS" -eq 0 ] && echo "✅ ПРОЙДЕНО: Критических проблем нет"
    echo ""
    echo "── Инвентарь сетей ────────────────────"
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

exit 0
