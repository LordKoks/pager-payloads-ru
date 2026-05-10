#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Обнаружение Вторжений (Intrusion Alert)
# Author: NullSec
# Description: Обнаружение сканирования портов, ARP-спуфинга и подозрительного трафика
# Category: nullsec/alerts

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/intrusionalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОБНАРУЖЕНИЕ ВТОРЖЕНИЙ

Лёгкая система обнаружения вторжений
для WiFi Pineapple Pager.

Обнаруживает:
- Сканирование портов
- ARP-спуфинг атаки
- SYN-флуды
- Аномальный DNS-трафик

Нажми OK для настройки."

# Определяем сетевой интерфейс
NET_IF=""
for iface in br-lan eth0 $IFACE; do
    [ -d "/sys/class/net/$iface" ] && NET_IF="$iface" && break
done

[ -z "$NET_IF" ] && { ERROR_DIALOG "Сетевой интерфейс не найден!"; exit 1; }

LOG "Используемый интерфейс: $NET_IF"

PROMPT "МОДУЛИ ОБНАРУЖЕНИЯ

Все модули включены:
- Обнаружение сканирования портов
- Обнаружение ARP-спуфинга
- Обнаружение SYN-флуда
- Обнаружение аномалий DNS

Нажми OK для установки длительности."

DURATION=$(NUMBER_PICKER "Время мониторинга (минуты):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

SCAN_THRESH=$(NUMBER_PICKER "Порог сканирования портов:" 20)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCAN_THRESH=20 ;; esac
[ "$SCAN_THRESH" -lt 5 ] && SCAN_THRESH=5

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ IDS?

Интерфейс: $NET_IF
Длительность: ${DURATION} мин
Порог сканирования: $SCAN_THRESH

Нажми OK для запуска.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/ids_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОБНАРУЖЕНИЯ ВТОРЖЕНИЙ ===" > "$LOG_FILE"
echo "Запущен: $(date)" >> "$LOG_FILE"
echo "Интерфейс: $NET_IF" >> "$LOG_FILE"
echo "===========================" >> "$LOG_FILE"

# Базовая таблица ARP
arp -i "$NET_IF" -n 2>/dev/null | awk '/ether/{print $1,$4}' | sort > /tmp/ids_arp_base.txt

END_TIME=$(($(date +%s) + DURATION * 60))
ALERT_COUNT=0
CYCLE=0

LOG "Мониторинг сети запущен..."
SPINNER_START "Мониторинг сети..."

while [ $(date +%s) -lt $END_TIME ]; do
    CYCLE=$((CYCLE + 1))
    ALERTS_THIS_CYCLE=0
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # --- Обнаружение сканирования портов ---
    SYN_COUNT=$(timeout 5 tcpdump -i "$NET_IF" -c 200 'tcp[tcpflags] & tcp-syn != 0' 2>/dev/null | \
        awk '{print $3}' | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')
    SYN_COUNT=${SYN_COUNT:-0}

    if [ "$SYN_COUNT" -ge "$SCAN_THRESH" ]; then
        SRC_IP=$(timeout 3 tcpdump -i "$NET_IF" -c 50 'tcp[tcpflags] & tcp-syn != 0' 2>/dev/null | \
            awk '{print $3}' | cut -d'.' -f1-4 | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
        ALERT_COUNT=$((ALERT_COUNT + 1))
        ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
        echo "[$TIMESTAMP] СКАНИРОВАНИЕ_ПОРТОВ от $SRC_IP ($SYN_COUNT SYN-пакетов)" >> "$LOG_FILE"
        LOG "Сканирование портов: $SRC_IP"
    fi

    # --- Обнаружение ARP-спуфинга ---
    arp -i "$NET_IF" -n 2>/dev/null | awk '/ether/{print $1,$4}' | sort > /tmp/ids_arp_now.txt
    while read -r ip mac; do
        OLD_MAC=$(grep "^$ip " /tmp/ids_arp_base.txt 2>/dev/null | awk '{print $2}')
        if [ -n "$OLD_MAC" ] && [ "$OLD_MAC" != "$mac" ]; then
            ALERT_COUNT=$((ALERT_COUNT + 1))
            ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
            echo "[$TIMESTAMP] ARP_SPOOF IP:$ip было:$OLD_MAC сейчас:$mac" >> "$LOG_FILE"
            LOG "ARP-спуфинг: $ip"
        fi
    done < /tmp/ids_arp_now.txt
    cp /tmp/ids_arp_now.txt /tmp/ids_arp_base.txt

    # --- Обнаружение SYN-флуда ---
    FLOOD=$(timeout 3 tcpdump -i "$NET_IF" -c 500 'tcp[tcpflags] == tcp-syn' 2>/dev/null | wc -l)
    if [ "$FLOOD" -ge 100 ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
        echo "[$TIMESTAMP] SYN_FLOOD $FLOOD SYN-пакетов за 3 сек" >> "$LOG_FILE"
        LOG "Обнаружен SYN-флуд!"
    fi

    # --- Обнаружение аномалий DNS ---
    DNS_COUNT=$(timeout 3 tcpdump -i "$NET_IF" -c 200 'port 53' 2>/dev/null | wc -l)
    if [ "$DNS_COUNT" -ge 150 ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
        echo "[$TIMESTAMP] DNS_АНОМАЛИЯ $DNS_COUNT запросов за 3 сек" >> "$LOG_FILE"
    fi

    # Показываем предупреждение, если были алерты
    if [ "$ALERTS_THIS_CYCLE" -gt 0 ]; then
        SPINNER_STOP
        PROMPT "⚠ ОБНАРУЖЕНО ВТОРЖЕНИЕ!

$ALERTS_THIS_CYCLE алертов за цикл
Всего алертов: $ALERT_COUNT

Подробности в журнале.

Нажми OK для продолжения."
        SPINNER_START "Мониторинг сети..."
    fi

    sleep 5
done

SPINNER_STOP
rm -f /tmp/ids_arp_base.txt /tmp/ids_arp_now.txt

echo "===========================" >> "$LOG_FILE"
echo "Завершён: $(date)" >> "$LOG_FILE"
echo "Всего алертов: $ALERT_COUNT" >> "$LOG_FILE"
echo "Циклов выполнено: $CYCLE" >> "$LOG_FILE"

PROMPT "МОНИТОРИНГ ЗАВЕРШЁН

Длительность: ${DURATION} мин
Всего обнаружено алертов: $ALERT_COUNT
Циклов сканирования: $CYCLE

Журнал сохранён в:
$LOG_FILE

Нажми OK для выхода."