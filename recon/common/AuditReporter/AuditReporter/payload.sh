#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Audit Reporter
# Author: bad-antics
# Description: Generates a professional WiFi security audit report with risk scoring and recommendations
# Category: nullsec/blue-team

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ОТЧЕТ АУДИТА

Оценка безопасности WiFi
Генератор отчета.

Сканирует сеть и
создает подробный отчет:

- Оценка рисков
- Анализ безопасности
- Выводы и рекомендации
- Полный инвентарь сетей

Сканирование: 30 секунд

Нажмите OK для аудита."

OUTDIR="/mmc/nullsec/blue-team/audit-reporter"
mkdir -p "$OUTDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$OUTDIR/audit_${TIMESTAMP}.txt"

SPINNER_START "Сканирование безопасности (30 с)..."
timeout 30 airodump-ng $IFACE -w /tmp/audit --output-format csv 2>/dev/null
SPINNER_STOP

CSV="/tmp/audit-01.csv"
[ ! -f "$CSV" ] && { ERROR_DIALOG "Нет данных сканирования!"; exit 1; }

SPINNER_START "Формирование отчета аудита..."

TOTAL=$(grep -cE "^([0-9A-Fa-f]{2}:){5}" "$CSV" 2>/dev/null || echo 0)
WPA3=$(grep -ci "WPA3" "$CSV" 2>/dev/null || echo 0)
WPA2=$(grep -i "WPA2" "$CSV" 2>/dev/null | grep -cvi "WPA3" || echo 0)
WEP=$(grep -ci "WEP" "$CSV" 2>/dev/null || echo 0)
OPEN=$(grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" 2>/dev/null | grep -ci "OPN" || echo 0)
CRITICAL=$((WEP + OPEN))

if [ "$TOTAL" -gt 0 ]; then
    RISK_PCT=$(( (CRITICAL * 100) / TOTAL ))
else
    RISK_PCT=0
fi

if [ "$RISK_PCT" -lt 10 ]; then RISK="LOW"
elif [ "$RISK_PCT" -lt 30 ]; then RISK="MEDIUM"
elif [ "$RISK_PCT" -lt 60 ]; then RISK="HIGH"
else RISK="CRITICAL"
fi

{
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  Отчет оценки безопасности WiFi NullSec         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "Дата:     $(date '+%B %d, %Y %H:%M')"
    echo "Инструмент:     NullSec Pineapple Suite"
    echo "Устройство:   WiFi Pineapple Pager"
    echo ""
    echo "═══ ОБЩИЙ ВЫВОД ════════════════════════════════"
    echo ""
    echo "  Всего сетей:      $TOTAL"
    echo "  Уровень риска:    $RISK ($RISK_PCT%)"
    echo "  Критические находки: $CRITICAL"
    echo ""
    echo "═══ РАСПРЕДЕЛЕНИЕ БЕЗОПАСНОСТИ ═════════════════"
    echo ""
    echo "  WPA3 (надежно):   $WPA3"
    echo "  WPA2 (стандарт):  $WPA2"
    echo "  WEP (ломко):      $WEP"
    echo "  Open (без шифр.): $OPEN"
    echo ""
    echo "═══ ВЫВОДЫ ═════════════════════════════════════"
    echo ""
    [ "$OPEN" -gt 0 ] && echo "  [CRITICAL] $OPEN открытая сеть(и) — отсутствует шифрование" && echo "  → Включите WPA3-SAE или WPA2-PSK" && echo ""
    [ "$WEP" -gt 0 ] && echo "  [HIGH] $WEP сеть(и) WEP — легко взламываются" && echo "  → Обновите до WPA3 или WPA2" && echo ""
    [ "$WPA3" -eq 0 ] && [ "$TOTAL" -gt 0 ] && echo "  [MEDIUM] Нет обнаруженных WPA3-сетей" && echo "  → Запланируйте переход на WPA3" && echo ""
    [ "$CRITICAL" -eq 0 ] && echo "  Критических находок не выявлено." && echo ""
    echo "═══ ИНВЕНТАРЬ СЕТЕЙ ═════════════════════════════"
    echo ""
    printf "  %-18s  %-4s  %-6s  %-12s  %s\n" "BSSID" "CH" "PWR" "SECURITY" "ESSID"
    echo "  ─────────────────  ────  ──────  ────────────  ──────────"
    grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | sort -t',' -k9 -n -r | \
        awk -F',' '{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$4); gsub(/^ +| +$/,"",$6); gsub(/^ +| +$/,"",$9); gsub(/^ +| +$/,"",$14); printf "  %-18s  %-4s  %-6s  %-12s  %s\n", $1, $4, $9" dBm", $6, ($14=="" ? "<hidden>" : $14)}'
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Только для авторизованного тестирования безопасности."
    echo "  Сгенерировано NullSec Pineapple Suite"
    echo "  © 2024-2026 bad-antics • NullSec Security"
} > "$REPORT"

SPINNER_STOP

rm -f /tmp/audit* 2>/dev/null

CONFIRMATION_DIALOG "📄 Отчет аудита сгенерирован\n\nСетей: $TOTAL\nУровень риска: $RISK ($RISK_PCT%)\nКритических: $CRITICAL\n\nОтчет: $REPORT"
