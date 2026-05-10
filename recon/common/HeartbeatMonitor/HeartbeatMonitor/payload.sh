#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Heartbeat Monitor
# Author: NullSec
# Description: Непрерывный мониторинг здоровья для долгих операций — предупреждения о CPU, памяти, температуре, хранилище и деградации интерфейса
# Category: nullsec/utility

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/heartbeat"
mkdir -p "$LOOT_DIR"

PROMPT "МОНИТОР СЕРДЦЕБИЕНИЯ

Долгосрочный мониторинг здоровья
для вашего Pineapple Pager.

Непрерывно отслеживает:
- Температуру CPU
- Давление памяти
- Заполнение хранилища
- Статус интерфейса WiFi
- Сбои процессов
- Батарею (если доступна)
- Среднюю нагрузку системы
- Подключение к сети

Предупреждает при превышении
порогов. Записывает все
метрики для анализа после
операции.

Нажмите OK для настройки."

TIMESTAMP=$(date +%Y%m%d_%H%M)
HEALTH_LOG="$LOOT_DIR/heartbeat_$TIMESTAMP.csv"
ALERT_LOG="$LOOT_DIR/alerts_$TIMESTAMP.log"
SUMMARY="$LOOT_DIR/summary_$TIMESTAMP.txt"

# Threshold configuration
PROMPT "УСТАНОВИТЬ ПОРОГИ

Предупреждения срабатывают при
превышении значений лимитов.

Показаны по умолчанию — настройте
на следующих экранах или оставьте
по умолчанию.

Нажмите OK для настройки."

TEMP_WARN=$(NUMBER_PICKER "Предупреждение температуры CPU (C):" 75)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TEMP_WARN=75 ;; esac

TEMP_CRIT=$(NUMBER_PICKER "Критическая температура CPU (C):" 85)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TEMP_CRIT=85 ;; esac

MEM_WARN=$(NUMBER_PICKER "Предупреждение использования памяти (%):" 80)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MEM_WARN=80 ;; esac

ХРАНИЛИЩЕ_WARN=$(NUMBER_PICKER "Предупреждение использования хранилища (%):" 90)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ХРАНИЛИЩЕ_WARN=90 ;; esac

INTERVAL=$(NUMBER_PICKER "Интервал проверки (сек):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=30 ;; esac
[ $INTERVAL -lt 10 ] && INTERVAL=10
[ $INTERVAL -gt 300 ] && INTERVAL=300

DURATION=$(NUMBER_PICKER "Длительность мониторинга (час):" 4)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=4 ;; esac
[ $DURATION -lt 1 ] && DURATION=1
[ $DURATION -gt 72 ] && DURATION=72

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ СЕРДЦЕБИЕНИЕ?

Интервал: ${INTERVAL}с
Длительность: ${DURATION}ч
Предупр. темп: ${TEMP_WARN}C
Крит. темп: ${TEMP_CRIT}C
Предупр. пам: ${MEM_WARN}%
Предупр. хран: ${ХРАНИЛИЩЕ_WARN}%

Работает в фоне.
Предупреждения на экране Pager.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# CSV header
echo "время,эпоха,темп_cpu_c,пам_всего_mb,пам_использовано_mb,пам_проц,нагрузка_1м,нагрузка_5м,нагрузка_15м,хранение_корень_проц,хранение_mmc_проц,состояние_wlan0,состояние_wlan1,процессы,время_работы_сек,предупреждение" > "$HEALTH_LOG"

echo "[$(date)] Монитор сердцебиения запущен" > "$ALERT_LOG"
echo "[$(date)] Пороги: предупреждение_темп=${TEMP_WARN}C критическая_темп=${TEMP_CRIT}C предупреждение_пам=${MEM_WARN}% предупреждение_хран=${ХРАНИЛИЩЕ_WARN}%" >> "$ALERT_LOG"

# Track stats
TOTAL_CHECKS=0
TOTAL_ALERTS=0
TEMP_PEAK=0
MEM_PEAK=0
LOAD_PEAK=0
IFACE_DROPS=0
PREV_WLAN0_STATE=""
PREV_WLAN1_STATE=""
HEALTH_HISTORY=""

END_TIME=$(($(date +%s) + DURATION * 3600))

SPINNER_START "Мониторинг сердцебиения..."

while [ $(date +%s) -lt $END_TIME ]; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    EPOCH=$(date +%s)
    ALERT_MSG=""

    # --- CPU Temperature ---
    CPU_TEMP=0
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        RAW_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
        CPU_TEMP=$((RAW_TEMP / 1000))
    fi
    [ $CPU_TEMP -gt $TEMP_PEAK ] && TEMP_PEAK=$CPU_TEMP

    if [ $CPU_TEMP -ge $TEMP_CRIT ]; then
        ALERT_MSG="${ALERT_MSG}КРИТИЧНО: CPU ${CPU_TEMP}C! "
        echo "[$NOW] КРИТИЧНО: Температура CPU ${CPU_TEMP}C превышает ${TEMP_CRIT}C" >> "$ALERT_LOG"
    elif [ $CPU_TEMP -ge $TEMP_WARN ]; then
        ALERT_MSG="${ALERT_MSG}ПРЕДУПР: CPU ${CPU_TEMP}C "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: Температура CPU ${CPU_TEMP}C превышает ${TEMP_WARN}C" >> "$ALERT_LOG"
    fi

    # --- Memory ---
    MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_AVAIL=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
    MEM_PCT=0
    [ $MEM_TOTAL -gt 0 ] && MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
    [ $MEM_PCT -gt $MEM_PEAK ] && MEM_PEAK=$MEM_PCT

    if [ $MEM_PCT -ge $MEM_WARN ]; then
        ALERT_MSG="${ALERT_MSG}ПАМ: ${MEM_PCT}% "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: Использование памяти ${MEM_PCT}% (${MEM_USED}/${MEM_TOTAL}MB)" >> "$ALERT_LOG"
    fi

    # --- Load Average ---
    LOAD_1=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    LOAD_5=$(cat /proc/loadavg 2>/dev/null | awk '{print $2}')
    LOAD_15=$(cat /proc/loadavg 2>/dev/null | awk '{print $3}')
    # Integer comparison for peak
    LOAD_INT=$(echo "$LOAD_1" | cut -d. -f1)
    [ -z "$LOAD_INT" ] && LOAD_INT=0
    [ $LOAD_INT -gt $LOAD_PEAK ] && LOAD_PEAK=$LOAD_INT

    # High load alert (>4 on embedded device is concerning)
    if [ $LOAD_INT -ge 4 ]; then
        ALERT_MSG="${ALERT_MSG}НАГРУЗКА: $LOAD_1 "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: Высокая средняя нагрузка $LOAD_1" >> "$ALERT_LOG"
    fi

    # --- Хранилище ---
    ХРАНИЛИЩЕ_ROOT=$(df / 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}')
    ХРАНИЛИЩЕ_MMC=$(df /mmc 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}')
    [ -z "$ХРАНИЛИЩЕ_ROOT" ] && ХРАНИЛИЩЕ_ROOT=0
    [ -z "$ХРАНИЛИЩЕ_MMC" ] && ХРАНИЛИЩЕ_MMC=0

    if [ $ХРАНИЛИЩЕ_ROOT -ge $ХРАНИЛИЩЕ_WARN ]; then
        ALERT_MSG="${ALERT_MSG}КОРЕНЬ: ${ХРАНИЛИЩЕ_ROOT}% "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: Корневое хранилище ${ХРАНИЛИЩЕ_ROOT}% заполнено" >> "$ALERT_LOG"
    fi
    if [ $ХРАНИЛИЩЕ_MMC -ge $ХРАНИЛИЩЕ_WARN ]; then
        ALERT_MSG="${ALERT_MSG}SD: ${ХРАНИЛИЩЕ_MMC}% "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: SD карта ${ХРАНИЛИЩЕ_MMC}% заполнена" >> "$ALERT_LOG"
    fi

    # --- WiFi Interface Status ---
    WLAN0_STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null || echo "absent")
    WLAN1_STATE=$(cat /sys/class/net/wlan1/operstate 2>/dev/null || echo "absent")

    # Detect interface state changes
    if [ -n "$PREV_WLAN0_STATE" ] && [ "$WLAN0_STATE" != "$PREV_WLAN0_STATE" ]; then
        IFACE_DROPS=$((IFACE_DROPS + 1))
        ALERT_MSG="${ALERT_MSG}$IFACE:$WLAN0_STATE "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: $IFACE состояние изменилось: $PREV_WLAN0_STATE -> $WLAN0_STATE" >> "$ALERT_LOG"
    fi
    if [ -n "$PREV_WLAN1_STATE" ] && [ "$WLAN1_STATE" != "$PREV_WLAN1_STATE" ]; then
        IFACE_DROPS=$((IFACE_DROPS + 1))
        ALERT_MSG="${ALERT_MSG}wlan1:$WLAN1_STATE "
        echo "[$NOW] ПРЕДУПРЕЖДЕНИЕ: wlan1 состояние изменилось: $PREV_WLAN1_STATE -> $WLAN1_STATE" >> "$ALERT_LOG"
    fi
    PREV_WLAN0_STATE="$WLAN0_STATE"
    PREV_WLAN1_STATE="$WLAN1_STATE"

    # --- Process count ---
    PROC_COUNT=$(ls /proc/[0-9]* -d 2>/dev/null | wc -l)

    # --- Uptime ---
    UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)

    # --- Log to CSV ---
    echo "$NOW,$EPOCH,$CPU_TEMP,$MEM_TOTAL,$MEM_USED,$MEM_PCT,$LOAD_1,$LOAD_5,$LOAD_15,$ХРАНИЛИЩЕ_ROOT,$ХРАНИЛИЩЕ_MMC,$WLAN0_STATE,$WLAN1_STATE,$PROC_COUNT,$UPTIME_SEC,${ALERT_MSG:-ok}" >> "$HEALTH_LOG"

    # --- Display alert on Pager screen ---
    if [ -n "$ALERT_MSG" ]; then
        TOTAL_ALERTS=$((TOTAL_ALERTS + 1))
        SPINNER_STOP

        PROMPT "⚠ ПРЕДУПРЕЖДЕНИЕ ЗДОРОВЬЯ #$TOTAL_ALERTS

$ALERT_MSG

CPU: ${CPU_TEMP}C
ПАМ: ${MEM_PCT}% использовано
Нагрузка: $LOAD_1
Корень: ${ХРАНИЛИЩЕ_ROOT}%
SD: ${ХРАНИЛИЩЕ_MMC}%
$IFACE: $WLAN0_STATE
wlan1: $WLAN1_STATE

Нажмите OK для продолжения
мониторинга."

        SPINNER_START "Мониторинг сердцебиения..."
    fi

    # Status update every 20 checks
    if [ $((TOTAL_CHECKS % 20)) -eq 0 ]; then
        ELAPSED=$(( ($(date +%s) - (END_TIME - DURATION * 3600)) / 60 ))
        REMAINING=$(( (END_TIME - $(date +%s)) / 60 ))
        SPINNER_STOP

        # Health grade
        GRADE="ЗДОРОВЫЙ"
        [ $CPU_TEMP -ge $TEMP_WARN ] && GRADE="ДЕГРАДИРОВАННЫЙ"
        [ $MEM_PCT -ge $MEM_WARN ] && GRADE="ДЕГРАДИРОВАННЫЙ"
        [ $CPU_TEMP -ge $TEMP_CRIT ] && GRADE="КРИТИЧЕСКИЙ"

        PROMPT "СТАТУС СЕРДЦЕБИЕНИЯ

Время работы: ${ELAPSED}м
Осталось: ${REMAINING}м
Проверок: $TOTAL_CHECKS
Предупреждений: $TOTAL_ALERTS

Статус: $GRADE
CPU: ${CPU_TEMP}C (пк:${TEMP_PEAK}C)
ПАМ: ${MEM_PCT}% (пк:${MEM_PEAK}%)
Нагрузка: $LOAD_1
Сбросов интерфейса: $IFACE_DROPS

Нажмите OK для продолжения."

        SPINNER_START "Мониторинг сердцебиения..."
    fi

    sleep "$INTERVAL"
done

SPINNER_STOP

# Generate summary report
ELAPSED_MIN=$(( DURATION * 60 ))
HEALTH_GRADE="ЗДОРОВЫЙ"
[ $TOTAL_ALERTS -gt 0 ] && HEALTH_GRADE="ДЕГРАДИРОВАННЫЙ"
[ $TOTAL_ALERTS -gt 10 ] && HEALTH_GRADE="ПЛОХОЙ"
[ $TEMP_PEAK -ge $TEMP_CRIT ] && HEALTH_GRADE="КРИТИЧЕСКИЙ"

cat > "$SUMMARY" << EOF
==========================================
   ОТЧЕТ МОНИТОРА СЕРДЦЕБИЕНИЯ NULLSEC
==========================================

Период мониторинга: $DURATION часов
Интервал проверки: ${INTERVAL}с
Всего проверок: $TOTAL_CHECKS
Всего предупреждений: $TOTAL_ALERTS

ОБЩЕЕ ЗДОРОВЬЕ: $HEALTH_GRADE

========= ПИКОВЫЕ ЗНАЧЕНИЯ =========

Температура CPU: ${TEMP_PEAK}C (предупр: ${TEMP_WARN}C)
Использование памяти:    ${MEM_PEAK}% (предупр: ${MEM_WARN}%)
Средняя нагрузка:    ${LOAD_PEAK} пик
Сбросов интерфейса: $IFACE_DROPS

========= КОНЕЧНОЕ СОСТОЯНИЕ =========

Темп CPU:  ${CPU_TEMP}C
Память:    ${MEM_PCT}% (${MEM_USED}/${MEM_TOTAL}MB)
Нагрузка:      $LOAD_1 / $LOAD_5 / $LOAD_15
Корень:      ${ХРАНИЛИЩЕ_ROOT}%
SD карта:   ${ХРАНИЛИЩЕ_MMC}%
$IFACE:     $WLAN0_STATE
wlan1:     $WLAN1_STATE
Процессы: $PROC_COUNT
Время работы:    ${UPTIME_SEC}с

========= СВОДКА ПРЕДУПРЕЖДЕНИЙ =========
$(cat "$ALERT_LOG")

==========================================
Сгенерировано NullSec HeartbeatMonitor
$(date)
==========================================
EOF

PROMPT "МОНИТОРИНГ ЗАВЕРШЕН

Длительность: ${DURATION}ч
Проверок: $TOTAL_CHECKS
Предупреждений: $TOTAL_ALERTS

ЗДОРОВЬЕ: $HEALTH_GRADE

Пик CPU: ${TEMP_PEAK}C
Пик ПАМ: ${MEM_PEAK}%
Сбросов интерфейса: $IFACE_DROPS

Нажмите OK для файлов."

PROMPT "ФАЙЛЫ СОХРАНЕНЫ

Журнал здоровья (CSV):
heartbeat_$TIMESTAMP.csv

Журнал предупреждений:
alerts_$TIMESTAMP.log

Сводный отчет:
summary_$TIMESTAMP.txt

Расположение: $LOOT_DIR/

CSV можно графировать в
Excel/LibreOffice для
визуальной временной шкалы
здоровья.

Нажмите OK для выхода."
