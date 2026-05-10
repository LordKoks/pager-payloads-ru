#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Быстрая диагностика NullSec
# Author: bad-antics
# Description: Комплексная системная диагностика и проверка здоровья
# Category: nullsec

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "БЫСТРАЯ ДИАГНОСТИКА
━━━━━━━━━━━━━━━━━━━━━━━━━
Полная проверка здоровья системы.

Нажмите ОК для запуска."

SPINNER_START "Запуск диагностики..."

# System info
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "N/A")
TOTAL_MEM=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "?")
FREE_MEM=$(free -m 2>/dev/null | awk '/Mem:/ {print $4}' || echo "?")
DISK_USE=$(df -h /mmc 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
DISK_FREE=$(df -h /mmc 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")

# Сеть
WLAN0_STATUS=$(iw dev $IFACE info 2>/dev/null | grep -c "ssid" && echo "UP" || echo "DOWN")
WLAN1_STATUS=$([ -d /sys/class/net/wlan1 ] && echo "UP" || echo "DOWN")
MON_STATUS=$([ -d /sys/class/net/wlan1mon ] && echo "ACTIVE" || echo "OFF")
IP_ADDR=$(ip -4 addr show $IFACE 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "N/A")

# Battery
BATT=$(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1 || echo "N/A")
CHARGING=$(cat /sys/class/power_supply/*/status 2>/dev/null | head -1 || echo "N/A")

# Temperature
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
[ -n "$TEMP" ] && TEMP="$((TEMP / 1000))°C" || TEMP="N/A"

# Process count
PROCS=$(ps aux 2>/dev/null | wc -l || echo "N/A")

SPINNER_STOP

PROMPT "СИСТЕМНАЯ ДИАГНОСТИКА
━━━━━━━━━━━━━━━━━━━━━━━━━
Упtime:  $UPTIME
Загрузка:    $LOAD
Память:  ${FREE_MEM}/${TOTAL_MEM}MB
Диск:    ${DISK_FREE} свободно ($DISK_USE)
Температура:    $TEMP
Процессы:   $PROCS
━━━━━━━━━━━━━━━━━━━━━━━━━
Батарея: ${BATT}% ($CHARGING)
━━━━━━━━━━━━━━━━━━━━━━━━━
$IFACE:   $WLAN0_STATUS ($IP_ADDR)
wlan1:   $WLAN1_STATUS
Монитор: $MON_STATUS"
