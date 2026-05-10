#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Слежение за трафиком
# Author: NullSec
# Description: Отслеживать использование пропускной способности и предупреждать при превышении порогов
# Category: nullsec/alerts

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# При отсутствии подключенных устройств показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/bandwidthalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О ТРАФИКЕ

Контролируйте использование сети и предупреждайте при превышении порогов.

Возможности:
- Отслеживание по клиентам
- Мониторинг TX/RX
- Оповещения при превышении
- Логирование использования

Нажмите ОК для настройки."

# Обнаружение сетевого интерфейса
NET_IF=""
for iface in br-lan $IFACE eth0; do
    [ -d "/sys/class/net/$iface" ] && NET_IF="$iface" && break
done
[ -z "$NET_IF" ] && { ERROR_DIALOG "Нет сетевого интерфейса!"; exit 1; }

LOG "Интерфейс: $NET_IF"

PROMPT "ПОРОГ ОПОВЕЩЕНИЯ:

Укажите лимит пропускной способности в KB/s.
Оповещение сработает, если любой клиент превысит этот уровень.

1. 100 KB/s (низкий)
2. 500 KB/s (средний)
3. 1000 KB/s (высокий)
4. Пользовательский

Выберите вариант."

THRESH_SEL=$(NUMBER_PICKER "Порог (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) THRESH_SEL=2 ;; esac

case $THRESH_SEL in
    1) BW_THRESH=100 ;;
    2) BW_THRESH=500 ;;
    3) BW_THRESH=1000 ;;
    4)
        BW_THRESH=$(NUMBER_PICKER "Лимит KB/s:" 500)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) BW_THRESH=500 ;; esac
        ;;
    *) BW_THRESH=500 ;;
esac
[ "$BW_THRESH" -lt 10 ] && BW_THRESH=10

DURATION=$(NUMBER_PICKER "Время мониторинга (мин):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

INTERVAL=$(NUMBER_PICKER "Интервал проверки (сек):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=10 ;; esac
[ "$INTERVAL" -lt 5 ] && INTERVAL=5
[ "$INTERVAL" -gt 60 ] && INTERVAL=60

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ МОНИТОРИНГ?

Интерфейс: $NET_IF
Порог: ${BW_THRESH} KB/s
Длительность: ${DURATION} мин
Интервал: ${INTERVAL} с

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/bw_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О ТРАФИКЕ ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "Порог: ${BW_THRESH} KB/s" >> "$LOG_FILE"
echo "============================" >> "$LOG_FILE"

# Получить начальные счетчики байт по клиентам
get_client_bytes() {
    local tmpfile="$1"
    > "$tmpfile"
    # Используем iptables или /proc/net/arp + статистику интерфейса
    while read -r ip mac; do
        [ -z "$ip" ] && continue
        # Получить количество байт через iptables или nf_conntrack
        bytes=$(iptables -L FORWARD -v -n -x 2>/dev/null | grep "$ip" | awk '{sum+=$2} END{print sum+0}')
        echo "$ip $mac $bytes" >> "$tmpfile"
    done < <(arp -i "$NET_IF" -n 2>/dev/null | awk '/ether/{print $1,$4}')
}

get_client_bytes /tmp/bw_prev.txt

END_TIME=$(($(date +%s) + DURATION * 60))
ALERT_COUNT=0
TOTAL_BYTES=0

LOG "Bandwidth monitoring started..."
SPINNER_START "Monitoring bandwidth..."

while [ $(date +%s) -lt $END_TIME ]; do
    sleep "$INTERVAL"

    # Получить статистику интерфейса
    RX1=$(cat "/sys/class/net/$NET_IF/statistics/rx_bytes" 2>/dev/null || echo 0)
    TX1=$(cat "/sys/class/net/$NET_IF/statistics/tx_bytes" 2>/dev/null || echo 0)
    sleep 1
    RX2=$(cat "/sys/class/net/$NET_IF/statistics/rx_bytes" 2>/dev/null || echo 0)
    TX2=$(cat "/sys/class/net/$NET_IF/statistics/tx_bytes" 2>/dev/null || echo 0)

    RX_RATE=$(( (RX2 - RX1) / 1024 ))
    TX_RATE=$(( (TX2 - TX1) / 1024 ))
    TOTAL_RATE=$((RX_RATE + TX_RATE))
    TOTAL_BYTES=$((TOTAL_BYTES + RX2 - RX1 + TX2 - TX1))

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Проверка по клиентам через station dump
    TOP_CLIENT=""
    TOP_RATE=0
    while read -r line; do
        [[ "$line" =~ Station ]] && CUR_MAC=$(echo "$line" | awk '{print $2}')
        if [[ "$line" =~ "rx bytes" ]]; then
            CUR_RX=$(echo "$line" | awk '{print $3}')
        fi
        if [[ "$line" =~ "tx bytes" ]]; then
            CUR_TX=$(echo "$line" | awk '{print $3}')
            CUR_TOTAL=$(( (CUR_RX + CUR_TX) / 1024 ))
            if [ "$CUR_TOTAL" -gt "$TOP_RATE" ]; then
                TOP_RATE=$CUR_TOTAL
                TOP_CLIENT=$CUR_MAC
            fi
        fi
    done < <(iw dev "$NET_IF" station dump 2>/dev/null)

    # Записать текущие скорости
    echo "[$TIMESTAMP] Total: ${TOTAL_RATE} KB/s (RX:${RX_RATE} TX:${TX_RATE})" >> "$LOG_FILE"

    # Проверка порога
    if [ "$TOTAL_RATE" -ge "$BW_THRESH" ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        echo "[$TIMESTAMP] ALERT: ${TOTAL_RATE} KB/s exceeds ${BW_THRESH} KB/s" >> "$LOG_FILE"
        [ -n "$TOP_CLIENT" ] && echo "  Top client: $TOP_CLIENT" >> "$LOG_FILE"
        LOG "BW alert: ${TOTAL_RATE} KB/s"

        SPINNER_STOP
        PROMPT "⚠ ПРЕВЫШЕНИЕ ТРАФИКА!

Текущий: ${TOTAL_RATE} KB/s
Лимит: ${BW_THRESH} KB/s
RX: ${RX_RATE} KB/s
TX: ${TX_RATE} KB/s
$([ -n "$TOP_CLIENT" ] && echo "Топ: $TOP_CLIENT")

Оповещений: $ALERT_COUNT

Нажмите ОК, чтобы продолжить."
        SPINNER_START "Monitoring..."
    fi
 done

SPINNER_STOP
rm -f /tmp/bw_prev.txt

TOTAL_MB=$((TOTAL_BYTES / 1048576))

echo "============================" >> "$LOG_FILE"
echo "Окончание: $(date)" >> "$LOG_FILE"
echo "Всего данных: ${TOTAL_MB} MB" >> "$LOG_FILE"
echo "Оповещений: $ALERT_COUNT" >> "$LOG_FILE"

PROMPT "МОНИТОРИНГ ТРАФИКА ЗАВЕРШЕН

Длительность: ${DURATION} мин
Всего данных: ${TOTAL_MB} MB
Сработало оповещений: $ALERT_COUNT

Журнал сохранён:
$LOG_FILE

Нажмите ОК, чтобы выйти."
