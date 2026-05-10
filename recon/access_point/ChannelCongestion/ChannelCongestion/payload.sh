#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Channel Congestion Analyzer
# Author: NullSec
# Description: Analyzes WiFi channel congestion across all bands, scores each channel, recommends optimal operating channel
# Category: nullsec/utility

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/congestion"
mkdir -p "$LOOT_DIR"

PROMPT "АНАЛИЗ ЗАГРУЗКИ КАНАЛОВ

Анализирует загруженность
WiFi каналов и находит
самый чистый канал для
работы.

Функции:
- Полное сканирование 2.4GHz (1-13)
- Сканирование 5GHz (36-165)
- Количество AP на канал
- Оценка силы сигнала
- Расчет перекрытия
- Счет загруженности 0-100
- Выбор оптимального канала
- Визуальный вид спектра

Нажмите OK для настройки."

# Find interface
IFACE=""
for ifc in wlan1 $IFACE; do
    if iw dev "$ifc" info >/dev/null 2>&1; then
        IFACE="$ifc"
        break
    fi
done

if [ -z "$IFACE" ]; then
    ERROR_DIALOG "WiFi интерфейс не найден!

Убедитесь, что WiFi адаптер
подключен."
    exit 1
fi

PROMPT "ОПЦИИ СКАНИРОВАНИЯ:

1. Только 2.4GHz (быстро)
   Каналы 1-13

2. Только 5GHz
   Каналы 36-165

3. Полный спектр
   Оба 2.4 + 5GHz

Интерфейс: $IFACE"

BAND=$(NUMBER_PICKER "Диапазон (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) BAND=1 ;; esac

PASSES=$(NUMBER_PICKER "Количество проходов (1-5):" 3)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PASSES=3 ;; esac
[ $PASSES -lt 1 ] && PASSES=1
[ $PASSES -gt 5 ] && PASSES=5

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ АНАЛИЗ?

Диапазон: $([ $BAND -eq 1 ] && echo '2.4GHz' || ([ $BAND -eq 2 ] && echo '5GHz' || echo 'Полный'))
Проходы: $PASSES
Интерфейс: $IFACE

Больше проходов = лучше
точность но медленнее.

~$((PASSES * 15))с оценка.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
REPORT="$LOOT_DIR/congestion_$TIMESTAMP.txt"
TMPDIR="/tmp/congestion_$$"
mkdir -p "$TMPDIR"

SPINNER_START "Сканирование спектра..."

# Define channel lists
CHANNELS_24="1 2 3 4 5 6 7 8 9 10 11 12 13"
CHANNELS_5="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"

case $BAND in
    1) CHANNELS="$CHANNELS_24" ;;
    2) CHANNELS="$CHANNELS_5" ;;
    3) CHANNELS="$CHANNELS_24 $CHANNELS_5" ;;
esac

# Initialize channel data files
for ch in $CHANNELS; do
    echo "0" > "$TMPDIR/ch${ch}_aps"
    echo "" > "$TMPDIR/ch${ch}_signals"
done

# Multi-pass scanning for accuracy
for pass in $(seq 1 $PASSES); do
    # Use iw scan
    ip link set "$IFACE" up 2>/dev/null
    SCAN_OUT=$(iw dev "$IFACE" scan 2>/dev/null)

    echo "$SCAN_OUT" | awk '
    /^BSS / { mac=$2; sub(/\(.*/, "", mac) }
    /freq:/ { freq=$2 }
    /signal:/ { signal=$2 }
    /SSID:/ {
        ssid=$2
        # Convert freq to channel
        ch = 0
        if (freq >= 2412 && freq <= 2484) {
            ch = (freq - 2407) / 5
            if (freq == 2484) ch = 14
        } else if (freq >= 5180 && freq <= 5825) {
            ch = (freq - 5000) / 5
        }
        if (ch > 0) print ch"|"signal"|"ssid"|"mac
    }
    ' > "$TMPDIR/pass_${pass}.txt" 2>/dev/null

    # Accumulate per-channel data
    while IFS='|' read -r ch signal ssid mac; do
        [ -z "$ch" ] && continue
        # Increment AP count
        current=$(cat "$TMPDIR/ch${ch}_aps" 2>/dev/null || echo 0)
        echo $((current + 1)) > "$TMPDIR/ch${ch}_aps"
        # Record signal strength
        echo "$signal" >> "$TMPDIR/ch${ch}_signals"
    done < "$TMPDIR/pass_${pass}.txt"

    sleep 2
done

SPINNER_STOP
SPINNER_START "Расчет оценок..."

# Calculate congestion score per channel
# Score formula: AP_density * 30 + signal_strength_factor * 40 + overlap_factor * 30
# Result: 0 (empty) to 100 (severely congested)

calc_congestion() {
    local ch="$1"
    local ap_total=$(cat "$TMPDIR/ch${ch}_aps" 2>/dev/null || echo 0)
    local ap_avg=$((ap_total / PASSES))

    # AP density score (0-30)
    local ap_score=0
    if [ $ap_avg -ge 15 ]; then ap_score=30
    elif [ $ap_avg -ge 10 ]; then ap_score=25
    elif [ $ap_avg -ge 7 ]; then ap_score=20
    elif [ $ap_avg -ge 5 ]; then ap_score=15
    elif [ $ap_avg -ge 3 ]; then ap_score=10
    elif [ $ap_avg -ge 1 ]; then ap_score=5
    fi

    # Signal strength score (0-40) — stronger signals = more interference
    local sig_score=0
    local sig_count=0
    local sig_sum=0
    while read -r sig; do
        [ -z "$sig" ] && continue
        # Remove negative sign and decimals
        sig_abs=$(echo "$sig" | tr -d '-' | cut -d. -f1)
        [ -z "$sig_abs" ] && continue
        sig_sum=$((sig_sum + sig_abs))
        sig_count=$((sig_count + 1))
    done < "$TMPDIR/ch${ch}_signals"

    if [ $sig_count -gt 0 ]; then
        local sig_avg=$((sig_sum / sig_count))
        # Lower dBm abs value = stronger signal = more congestion
        if [ $sig_avg -le 40 ]; then sig_score=40
        elif [ $sig_avg -le 50 ]; then sig_score=35
        elif [ $sig_avg -le 60 ]; then sig_score=25
        elif [ $sig_avg -le 70 ]; then sig_score=15
        elif [ $sig_avg -le 80 ]; then sig_score=8
        else sig_score=3
        fi
    fi

    # Overlap score (0-30) — 2.4GHz channels overlap +-2
    local overlap_score=0
    if [ "$ch" -le 13 ] 2>/dev/null; then
        for offset in -2 -1 1 2; do
            neighbor=$((ch + offset))
            [ $neighbor -lt 1 ] && continue
            [ $neighbor -gt 13 ] && continue
            neighbor_aps=$(cat "$TMPDIR/ch${neighbor}_aps" 2>/dev/null || echo 0)
            neighbor_avg=$((neighbor_aps / PASSES))
            overlap_score=$((overlap_score + neighbor_avg * 2))
        done
        [ $overlap_score -gt 30 ] && overlap_score=30
    fi
    # 5GHz channels don't overlap (non-bonded)

    local total=$((ap_score + sig_score + overlap_score))
    [ $total -gt 100 ] && total=100

    echo "${total}|${ap_avg}|${sig_score}|${overlap_score}"
}

# Build visual bar
make_bar() {
    local score=$1
    local max_width=16
    local filled=$((score * max_width / 100))
    local bar=""
    local i=0
    while [ $i -lt $filled ]; do
        bar="${bar}#"
        i=$((i + 1))
    done
    while [ $i -lt $max_width ]; do
        bar="${bar}-"
        i=$((i + 1))
    done
    echo "$bar"
}

grade_channel() {
    local score=$1
    if [ $score -le 10 ]; then echo "ОТЛИЧНЫЙ"
    elif [ $score -le 25 ]; then echo "ХОРОШИЙ"
    elif [ $score -le 50 ]; then echo "УМЕРЕННЫЙ"
    elif [ $score -le 75 ]; then echo "ЗАГРУЖЕННЫЙ"
    else echo "СЕРЬЕЗНЫЙ"
    fi
}

# Calculate all channels
BEST_CH=""
BEST_SCORE=101
WORST_CH=""
WORST_SCORE=-1

cat > "$REPORT" << HEADER
==========================================
   ОТЧЕТ О ЗАГРУЗКЕ КАНАЛОВ NULLSEC
==========================================

Время сканирования: $(date)
Интерфейс: $IFACE
Проходы: $PASSES
Диапазон: $([ $BAND -eq 1 ] && echo '2.4GHz' || ([ $BAND -eq 2 ] && echo '5GHz' || echo 'Полный спектр'))

Оценка: 0 (пустой) → 100 (серьезно загруженный)

HEADER

# 2.4GHz Analysis
if [ $BAND -eq 1 ] || [ $BAND -eq 3 ]; then
    echo "========== СПЕКТР 2.4 ГГц ==========" >> "$REPORT"
    echo "" >> "$REPORT"
    printf "%-4s %-4s %-5s %-18s %s\n" "КАН" "AP" "ОЦЕНКА" "ЗАГРУЗКА" "СТЕПЕНЬ" >> "$REPORT"
    echo "--------------------------------------------" >> "$REPORT"

    PAGER_24=""
    for ch in $CHANNELS_24; do
        RESULT=$(calc_congestion "$ch")
        SCORE=$(echo "$RESULT" | cut -d'|' -f1)
        APS=$(echo "$RESULT" | cut -d'|' -f2)
        BAR=$(make_bar "$SCORE")
        GRADE=$(grade_channel "$SCORE")

        printf "%-4s %-4s %-5s [%-16s] %s\n" "$ch" "$APS" "$SCORE" "$BAR" "$GRADE" >> "$REPORT"

        # Build Pager display (compact)
        PAGER_24="${PAGER_24}кан${ch}: ${SCORE}/100 (${APS}ТД) $GRADE\n"

        # Track best/worst
        if [ $SCORE -lt $BEST_SCORE ]; then
            BEST_SCORE=$SCORE; BEST_CH=$ch
        fi
        if [ $SCORE -gt $WORST_SCORE ]; then
            WORST_SCORE=$SCORE; WORST_CH=$ch
        fi
    done
    echo "" >> "$REPORT"

    # Non-overlapping channel recommendation
    CH1_SCORE=$(calc_congestion 1 | cut -d'|' -f1)
    CH6_SCORE=$(calc_congestion 6 | cut -d'|' -f1)
    CH11_SCORE=$(calc_congestion 11 | cut -d'|' -f1)

    echo "--- НЕПЕРЕКРЫВАЮЩИЕСЯ КАНАЛЫ ---" >> "$REPORT"
    echo "Кан 1:  Оценка $CH1_SCORE — $(grade_channel $CH1_SCORE)" >> "$REPORT"
    echo "Кан 6:  Оценка $CH6_SCORE — $(grade_channel $CH6_SCORE)" >> "$REPORT"
    echo "Кан 11: Оценка $CH11_SCORE — $(grade_channel $CH11_SCORE)" >> "$REPORT"
    echo "" >> "$REPORT"

    # Smart recommendation
    RECOMMENDED=1
    if [ $CH6_SCORE -lt $CH1_SCORE ] && [ $CH6_SCORE -lt $CH11_SCORE ]; then
        RECOMMENDED=6
    elif [ $CH11_SCORE -lt $CH1_SCORE ]; then
        RECOMMENDED=11
    fi
    echo "РЕКОМЕНДУЕМЫЙ: Канал $RECOMMENDED (Оценка: $(calc_congestion $RECOMMENDED | cut -d'|' -f1))" >> "$REPORT"
    echo "" >> "$REPORT"
fi

# 5GHz Analysis
if [ $BAND -eq 2 ] || [ $BAND -eq 3 ]; then
    echo "=========== СПЕКТР 5 ГГц ===========" >> "$REPORT"
    echo "" >> "$REPORT"
    printf "%-5s %-4s %-5s %-18s %s\n" "КАН" "AP" "ОЦЕНКА" "ЗАГРУЗКА" "СТЕПЕНЬ" >> "$REPORT"
    echo "----------------------------------------------" >> "$REPORT"

    PAGER_5=""
    for ch in $CHANNELS_5; do
        RESULT=$(calc_congestion "$ch")
        SCORE=$(echo "$RESULT" | cut -d'|' -f1)
        APS=$(echo "$RESULT" | cut -d'|' -f2)
        BAR=$(make_bar "$SCORE")
        GRADE=$(grade_channel "$SCORE")

        printf "%-5s %-4s %-5s [%-16s] %s\n" "$ch" "$APS" "$SCORE" "$BAR" "$GRADE" >> "$REPORT"
        PAGER_5="${PAGER_5}кан${ch}: ${SCORE}/100 $GRADE\n"

        if [ $SCORE -lt $BEST_SCORE ]; then
            BEST_SCORE=$SCORE; BEST_CH=$ch
        fi
        if [ $SCORE -gt $WORST_SCORE ]; then
            WORST_SCORE=$SCORE; WORST_CH=$ch
        fi
    done
    echo "" >> "$REPORT"
fi

# Overall summary
TOTAL_APS=0
for ch in $CHANNELS; do
    ch_aps=$(cat "$TMPDIR/ch${ch}_aps" 2>/dev/null || echo 0)
    TOTAL_APS=$((TOTAL_APS + ch_aps / PASSES))
done

cat >> "$REPORT" << FOOTER

============ РЕКОМЕНДАЦИЯ =============

ЛУЧШИЙ канал:  $BEST_CH (оценка: $BEST_SCORE — $(grade_channel $BEST_SCORE))
ХУДШИЙ канал: $WORST_CH (оценка: $WORST_SCORE — $(grade_channel $WORST_SCORE))
Всего AP увидено: ~$TOTAL_APS (усреднено за $PASSES проходов)

СОВЕТ: Для операций Pineapple, используйте
канал $BEST_CH для чистейшего сигнала.
Избегайте канал $WORST_CH.

Для атак evil twin, соответствуйте каналу
целевого AP.

==========================================
Сгенерировано NullSec ChannelCongestion
$(date)
==========================================
FOOTER

# Cleanup
rm -rf "$TMPDIR"

SPINNER_STOP

# Display on Pager
PROMPT "АНАЛИЗ ЗАГРУЗКИ

Всего AP: ~$TOTAL_APS
Каналов просканировано: $(echo $CHANNELS | wc -w)

ЛУЧШИЙ: Канал $BEST_CH
Оценка: $BEST_SCORE/100
$(grade_channel $BEST_SCORE)

ХУДШИЙ: Канал $WORST_CH
Оценка: $WORST_SCORE/100
$(grade_channel $WORST_SCORE)

Нажмите OK для разбивки."

if [ $BAND -eq 1 ] || [ $BAND -eq 3 ]; then
    PROMPT "2.4GHz НЕПЕРЕКРЫТИЕ

Кан 1:  $CH1_SCORE/100
Кан 6:  $CH6_SCORE/100
Кан 11: $CH11_SCORE/100

Рекомендуемый: Кан $RECOMMENDED

Нижняя оценка = чище.

Нажмите OK для продолжения."
fi

if [ $BAND -eq 1 ] || [ $BAND -eq 3 ]; then
    PROMPT "ВСЕ КАНАЛЫ 2.4GHz

$(echo -e "$PAGER_24")
Нажмите OK для продолжения."
fi

if [ $BAND -eq 2 ] || [ $BAND -eq 3 ]; then
    PROMPT "КАНАЛЫ 5GHz

$(echo -e "$PAGER_5" | head -15)
Нажмите OK для продолжения."
fi

PROMPT "ОТЧЕТ СОХРАНЕН

congestion_$TIMESTAMP.txt

Расположение: $LOOT_DIR/

Используйте канал $BEST_CH для
оптимальных операций.

Нажмите OK для выхода."
