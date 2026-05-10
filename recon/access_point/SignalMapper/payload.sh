#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Карта сигнала
# Author: bad-antics
# Description: Построение карты уровня WiFi-сигнала в нескольких точках
# Category: nullsec/blue-team

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "КАРТА СИГНАЛА

Много точечное построение
карты уровня WiFi-сигнала.

Собирает данные в 3 точках
для анализа покрытия.

Перемещай устройство между
сканированиями.

Нажми OK для запуска."

OUTDIR="/mmc/nullsec/blue-team/signal-mapper"
mkdir -p "$OUTDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAPFILE="$OUTDIR/signal_map_${TIMESTAMP}.csv"
REPORT="$OUTDIR/signal_report_${TIMESTAMP}.txt"

echo "образец,время,bssid,essid,канал,мощность,безопасность" > "$MAPFILE"

SAMPLES=3
SAMPLE_TIME=10

for POINT in 1 2 3; do
    if [ "$POINT" -gt 1 ]; then
        PROMPT "ТОЧКА $POINT из $SAMPLES\n\nПерейди в новое место,\nзатем нажми OK для сканирования."
    fi

    SPINNER_START "Точка $POINT/$SAMPLES (${SAMPLE_TIME} сек)..."
    timeout $SAMPLE_TIME airodump-ng $IFACE -w /tmp/sigmap_${POINT} --output-format csv 2>/dev/null
    SPINNER_STOP

    CSV="/tmp/sigmap_${POINT}-01.csv"
    if [ -f "$CSV" ]; then
        grep -E "^([0-9A-Fa-f]{2}:){5}" "$CSV" | \
            awk -F',' -v pt="$POINT" -v ts="$(date +%H:%M:%S)" '{
                gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$14);
                gsub(/^ +| +$/,"",$4); gsub(/^ +| +$/,"",$9); gsub(/^ +| +$/,"",$6);
                printf "%s,%s,%s,%s,%s,%s,%s\n", pt, ts, $1, $14, $4, $9, $6
            }' >> "$MAPFILE"
    fi
    rm -f /tmp/sigmap_${POINT}* 2>/dev/null
done

SPINNER_START "Анализ покрытия..."

UNIQUE_APS=$(tail -n +2 "$MAPFILE" | awk -F',' '{print $3}' | sort -u | wc -l)
FULL_COV=$(tail -n +2 "$MAPFILE" | awk -F',' '{print $1","$3}' | sort -u | \
    awk -F',' '{count[$2]++} END {for(k in count) if(count[k]>=3) c++; print c+0}')

{
    echo "╔═══════════════════════════════════════╗"
    echo "║     Отчёт карты сигнала NullSec       ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Дата: $(date)"
    echo "Точек сканирования: $SAMPLES"
    echo "Уникальных точек доступа: $UNIQUE_APS"
    echo "Полное покрытие: $FULL_COV"
    echo "Частичное покрытие: $((UNIQUE_APS - FULL_COV))"
    echo ""
    echo "── Уровень сигнала по точкам доступа ──"
    tail -n +2 "$MAPFILE" | awk -F',' '{key=$3; name[$3]=$4; sum[key]+=$6; count[key]++; if(!max[key]||$6>max[key]) max[key]=$6; if(!min[key]||$6<min[key]) min[key]=$6} END {for(k in sum) printf "%-18s %-15s СР:%4.0f МИН:%d МАКС:%d (%d тчк)\n", k, name[k], sum[k]/count[k], min[k], max[k], count[k]}'
    echo ""
    echo "CSV-файл: $MAPFILE"
} > "$REPORT"

SPINNER_STOP

CONFIRMATION_DIALOG "📊 Карта сигнала построена\n\nТочек сканирования: $SAMPLES\nУникальных AP: $UNIQUE_APS\nПолное покрытие: $FULL_COV\nЧастичное: $((UNIQUE_APS - FULL_COV))\n\nОтчёт: $REPORT"