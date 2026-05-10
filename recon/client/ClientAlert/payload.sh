#!/bin/bash
# Title: Client Alert
# Author: NullSec
# Description: Alerts when new clients connect to the Pineapple AP
# Category: nullsec/alerts

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/clientalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О КЛИЕНТАХ

Мониторинг новых клиентов,
подключающихся к вашей ТД.

Функции:
- Обнаружение подключений
- Логирование MAC-адресов
- Идентификация производителя
- Оповещения в реальном времени

Нажмите OK для настройки."

# Check AP interface
AP_IF=""
for iface in $IFACE br-lan; do
    [ -d "/sys/class/net/$iface" ] && AP_IF="$iface" && break
done
[ -z "$AP_IF" ] && { ERROR_DIALOG "Интерфейс ТД не найден!

Убедитесь, что Pineapple AP
запущен."; exit 1; }

LOG "AP interface: $AP_IF"

DURATION=$(NUMBER_PICKER "Мониторинг (минуты):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

POLL_RATE=$(NUMBER_PICKER "Интервал проверки (сек):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) POLL_RATE=10 ;; esac
[ "$POLL_RATE" -lt 3 ] && POLL_RATE=3
[ "$POLL_RATE" -gt 60 ] && POLL_RATE=60

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ОПОВЕЩЕНИЕ О КЛИЕНТАХ?

Интерфейс: $AP_IF
Длительность: ${DURATION} мин
Частота опроса: ${POLL_RATE}с

Нажмите OK для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/clients_$(date +%Y%m%d_%H%M).log"
echo "=== CLIENT ALERT LOG ===" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "Интерфейс: $AP_IF" >> "$LOG_FILE"
echo "========================" >> "$LOG_FILE"

# Vendor lookup function
get_vendor() {
    local mac_prefix=$(echo "$1" | tr -d ':' | head -c 6 | tr 'a-f' 'A-F')
    local vendor=""
    if [ -f /usr/share/ieee-oui.txt ]; then
        vendor=$(grep -i "$mac_prefix" /usr/share/ieee-oui.txt 2>/dev/null | head -1 | cut -d')' -f2 | sed 's/^[[:space:]]*//')
    elif [ -f /etc/oui.txt ]; then
        vendor=$(grep -i "$mac_prefix" /etc/oui.txt 2>/dev/null | head -1 | awk -F'\t' '{print $NF}')
    fi
    [ -z "$vendor" ] && vendor="Unknown"
    echo "$vendor" | head -c 20
}

# Snapshot current clients
arp -i "$AP_IF" -n 2>/dev/null | awk '/ether/{print $4}' | sort -u > /tmp/ca_known.txt
iw dev "$AP_IF" station dump 2>/dev/null | awk '/Station/{print $2}' | sort -u >> /tmp/ca_known.txt
sort -u /tmp/ca_known.txt -o /tmp/ca_known.txt

KNOWN=$(wc -l < /tmp/ca_known.txt)
NEW_COUNT=0
END_TIME=$(($(date +%s) + DURATION * 60))

LOG "Monitoring clients (${KNOWN} initial)..."
SPINNER_START "Watching for new clients..."

while [ $(date +%s) -lt $END_TIME ]; do
    sleep "$POLL_RATE"

    # Get current clients from ARP and station dump
    arp -i "$AP_IF" -n 2>/dev/null | awk '/ether/{print $4}' | sort -u > /tmp/ca_current.txt
    iw dev "$AP_IF" station dump 2>/dev/null | awk '/Station/{print $2}' | sort -u >> /tmp/ca_current.txt
    sort -u /tmp/ca_current.txt -o /tmp/ca_current.txt

    # Find new clients
    NEW_MACS=$(comm -13 /tmp/ca_known.txt /tmp/ca_current.txt 2>/dev/null)

    if [ -n "$NEW_MACS" ]; then
        while IFS= read -r MAC; do
            [ -z "$MAC" ] && continue
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            VENDOR=$(get_vendor "$MAC")
            IP=$(arp -n 2>/dev/null | grep -i "$MAC" | awk '{print $1}' | head -1)
            [ -z "$IP" ] && IP="pending"

            NEW_COUNT=$((NEW_COUNT + 1))
            echo "[$TIMESTAMP] NEW: $MAC ($VENDOR) IP:$IP" >> "$LOG_FILE"
            LOG "New client: $MAC"

            SPINNER_STOP
            PROMPT "⚠ НОВЫЙ КЛИЕНТ!

MAC: $MAC
Производитель: $VENDOR
IP: $IP
Время: $TIMESTAMP

Всего новых: $NEW_COUNT

Нажмите OK для продолжения."
            SPINNER_START "Watching..."
        done <<< "$NEW_MACS"

        cp /tmp/ca_current.txt /tmp/ca_known.txt
    fi
done

SPINNER_STOP
rm -f /tmp/ca_known.txt /tmp/ca_current.txt

echo "========================" >> "$LOG_FILE"
echo "Ended: $(date)" >> "$LOG_FILE"
echo "New clients: $NEW_COUNT" >> "$LOG_FILE"

PROMPT "ОПОВЕЩЕНИЕ О КЛИЕНТАХ ЗАВЕРШЕНО

Длительность: ${DURATION} мин
Начальных клиентов: $KNOWN
Новых клиентов: $NEW_COUNT

Лог сохранен в:
$LOG_FILE

Нажмите OK для выхода."
