#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Анализатор спектра
# Author: NullSec
# Description: Анализ WiFi-спектра с оценкой загрузки каналов и поиском помех
# Category: nullsec/recon

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/spectrum"
mkdir -p "$LOOT_DIR"

PROMPT "АНАЛИЗАТОР СПЕКТРА

Анализ WiFi-спектра
по каналам 1-14.

Возможности:
- Загрузка каналов
- Карта помех
- Обзор уровня сигнала
- Плотность точек доступа
- Рекомендация лучшего канала

Нажми OK для настройки."

# Поиск мониторного интерфейса
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0 wlan1 $IFACE; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Интерфейс не найден!"; exit 1; }

PROMPT "РЕЖИМ АНАЛИЗА:

1. Быстрое обследование каналов
2. Глубокий анализ спектра
3. Поиск помех
4. Рекомендация лучшего канала

Интерфейс: $MONITOR_IF

Выбери режим:"

SCAN_MODE=$(NUMBER_PICKER "Режим (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_MODE=1 ;; esac

BAND=$(CONFIRMATION_DIALOG "Включить 5 ГГц?

ДА = 2.4 ГГц + 5 ГГц
НЕТ = только 2.4 ГГц

Примечание: 5 ГГц требует
поддержки оборудования.")
if [ "$BAND" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    CHANNELS="1-14,36,40,44,48,52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,149,153,157,161,165"
    BAND_NAME="2.4 + 5 ГГц"
else
    CHANNELS="1-14"
    BAND_NAME="2.4 ГГц"
fi

SCAN_TIME=$(NUMBER_PICKER "Время сканирования (секунды):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_TIME=60 ;; esac
[ $SCAN_TIME -lt 20 ] && SCAN_TIME=20
[ $SCAN_TIME -gt 300 ] && SCAN_TIME=300

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ АНАЛИЗ СПЕКТРА?

Режим: $SCAN_MODE
Диапазон: $BAND_NAME
Длительность: ${SCAN_TIME} сек
Интерфейс: $MONITOR_IF

Подтверждаешь?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
REPORT="$LOOT_DIR/spectrum_$TIMESTAMP.txt"
CAP_PREFIX="/tmp/spectrum_$$"

LOG "Запуск анализа спектра..."
SPINNER_START "Анализ WiFi-спектра..."

# Запуск airodump-ng
timeout "$SCAN_TIME" airodump-ng "$MONITOR_IF" -c "$CHANNELS" \
    --write-interval 3 -w "$CAP_PREFIX" --output-format csv 2>/dev/null &
SCAN_PID=$!
sleep "$SCAN_TIME"
kill $SCAN_PID 2>/dev/null
wait $SCAN_PID 2>/dev/null

# Поиск созданного CSV-файла
CSV_FILE=$(ls -t "${CAP_PREFIX}"*.csv 2>/dev/null | head -1)
[ -z "$CSV_FILE" ] && { SPINNER_STOP; ERROR_DIALOG "Данные сканирования не получены!"; exit 1; }

echo "=======================================" > "$REPORT"
echo "    ОТЧЁТ АНАЛИЗАТОРА СПЕКТРА NULLSEC   " >> "$REPORT"
echo "=======================================" >> "$REPORT"
echo "" >> "$REPORT"
echo "Время сканирования: $(date)" >> "$REPORT"
echo "Длительность: ${SCAN_TIME} сек" >> "$REPORT"
echo "Диапазон: $BAND_NAME" >> "$REPORT"
echo "Интерфейс: $MONITOR_IF" >> "$REPORT"
echo "" >> "$REPORT"

# Анализ загрузки каналов
echo "--- ЗАГРУЗКА КАНАЛОВ ---" >> "$REPORT"
echo "" >> "$REPORT"

declare -A CH_COUNT
declare -A CH_POWER
TOTAL_APS=0

while IFS=',' read -r bssid first last channel speed privacy cipher auth power beacons iv lanip idlen essid rest; do
    channel=$(echo "$channel" | tr -d ' ')
    power=$(echo "$power" | tr -d ' ')
    [[ "$channel" =~ ^[0-9]+$ ]] || continue
    [ -z "$channel" ] && continue

    CH_COUNT[$channel]=$(( ${CH_COUNT[$channel]:-0} + 1 ))
    TOTAL_APS=$((TOTAL_APS + 1))

    if [ -n "$power" ] && [ "$power" -ne -1 ] 2>/dev/null; then
        if [ -z "${CH_POWER[$channel]}" ] || [ "$power" -gt "${CH_POWER[$channel]}" ]; then
            CH_POWER[$channel]=$power
        fi
    fi
done < "$CSV_FILE"

# Вывод гистограммы каналов
echo "Канал | ТД  | Сигнал | Загрузка" >> "$REPORT"
echo "------|-----|--------|---------" >> "$REPORT"

BEST_CH=""
BEST_CH_COUNT=999

for ch in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    count=${CH_COUNT[$ch]:-0}
    power=${CH_POWER[$ch]:-"n/a"}

    BAR=""
    for i in $(seq 1 $count); do
        BAR="${BAR}#"
    done
    [ $count -eq 0 ] && BAR="-"

    printf "%2d   | %3d | %6s | %s\n" "$ch" "$count" "$power" "$BAR" >> "$REPORT"

    if [ $count -lt $BEST_CH_COUNT ]; then
        BEST_CH_COUNT=$count
        BEST_CH=$ch
    fi
done

echo "" >> "$REPORT"

# 5 ГГц каналы (если сканировались)
if [ "$BAND" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    echo "--- КАНАЛЫ 5 ГГц ---" >> "$REPORT"
    echo "" >> "$REPORT"
    for ch in 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165; do
        count=${CH_COUNT[$ch]:-0}
        [ $count -gt 0 ] && printf "Канал %3d | %3d ТД\n" "$ch" "$count" >> "$REPORT"
    done
    echo "" >> "$REPORT"
fi

# Анализ помех
if [ "$SCAN_MODE" -ge 3 ]; then
    echo "--- АНАЛИЗ ПОМЕХ ---" >> "$REPORT"
    echo "" >> "$REPORT"

    for ch in 1 6 11; do
        OVERLAP=0
        case $ch in
            1) for o in 2 3 4 5; do OVERLAP=$((OVERLAP + ${CH_COUNT[$o]:-0})); done ;;
            6) for o in 3 4 5 7 8 9; do OVERLAP=$((OVERLAP + ${CH_COUNT[$o]:-0})); done ;;
            11) for o in 8 9 10 12 13; do OVERLAP=$((OVERLAP + ${CH_COUNT[$o]:-0})); done ;;
        esac
        echo "Канал $ch: ${CH_COUNT[$ch]:-0} ТД, пересечений: $OVERLAP" >> "$REPORT"
    done
    echo "" >> "$REPORT"
fi

# Рекомендация лучшего канала
echo "--- РЕКОМЕНДАЦИЯ ---" >> "$REPORT"
echo "" >> "$REPORT"

for ch in 1 6 11; do
    count=${CH_COUNT[$ch]:-0}
    if [ $count -le ${BEST_CH_COUNT:-999} ]; then
        BEST_CH=$ch
        BEST_CH_COUNT=$count
    fi
done

echo "Лучший канал: $BEST_CH (${BEST_CH_COUNT} точек доступа)" >> "$REPORT"
echo "Всего точек доступа: $TOTAL_APS" >> "$REPORT"
echo "" >> "$REPORT"
echo "=======================================" >> "$REPORT"

# Очистка
rm -f "${CAP_PREFIX}"* 2>/dev/null

SPINNER_STOP

PROMPT "АНАЛИЗ СПЕКТРА ЗАВЕРШЁН

Всего точек доступа: $TOTAL_APS
Лучший канал: $BEST_CH
  (${BEST_CH_COUNT} ТД)

Канал 1: ${CH_COUNT[1]:-0} ТД
Канал 6: ${CH_COUNT[6]:-0} ТД
Канал 11: ${CH_COUNT[11]:-0} ТД

Отчёт: $REPORT

Нажми OK для выхода."