#!/bin/bash
# Название: Оповещение о пропускной способности
# Автор: NullSec
# Описание: Мониторинг использования пропускной способности и оповещение при превышении порогов
# Категория: nullsec/alerts

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/bandwidthalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О ПРОПУСКНОЙ СПОСОБНОСТИ

Мониторинг использования
сетевой пропускной способности
и оповещение при превышении
пороговых значений.

Возможности:
- Отслеживание по клиентам
- Мониторинг TX/RX
- Пороговые оповещения
- Журналирование использования

Нажмите ОК для настройки."

# Определение сетевого интерфейса
NET_IF=""
for iface in br-lan $IFACE eth0; do
    [ -d "/sys/class/net/$iface" ] && NET_IF="$iface" && break
done
[ -z "$NET_IF" ] && { ERROR_DIALOG "Сетевой интерфейс не найден!"; exit 1; }

LOG "Интерфейс: $NET_IF"

PROMPT "ПОРОГ ОПОВЕЩЕНИЯ:

Установите ограничение пропускной
способности в КБ/с. Оповещение
срабатывает при превышении
этого значения любым клиентом.

1. 100 КБ/с (низкий)
2. 500 КБ/с (средний)
3. 1000 КБ/с (высокий)
4. Свой вариант

Выберите следующий вариант."

THRESH_SEL=$(NUMBER_PICKER "Порог (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) THRESH_SEL=2 ;; esac

case $THRESH_SEL in
    1) BW_THRESH=100 ;;
    2) BW_THRESH=500 ;;
    3) BW_THRESH=1000 ;;
    4)
        BW_THRESH=$(NUMBER_PICKER "Ограничение КБ/с:" 500)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) BW_THRESH=500 ;; esac
        ;;
    *) BW_THRESH=500 ;;
esac
[ "$BW_THRESH" -lt 10 ] && BW_THRESH=10

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

INTERVAL=$(NUMBER_PICKER "Интервал проверки (сек):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=10 ;; esac
[ "$INTERVAL" -lt 5 ] && INTERVAL=5
[ "$INTERVAL" -gt 60 ] && INTERVAL=60

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ МОНИТОРИНГ?

Интерфейс: $NET_IF
Порог: ${BW_THRESH} КБ/с
Длительность: ${DURATION} мин
Интервал: ${INTERVAL} с

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/bw_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О ПРОПУСКНОЙ СПОСОБНОСТИ ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "Порог: ${BW_THRESH} КБ/с" >> "$LOG_FILE"
echo "============================" >> "$LOG_FILE"

# Получение начальных счетчиков байтов по клиентам
get_client_bytes() {
    local tmpfile="$1"
    > "$tmpfile"
    # Использование учёта iptables или /proc/net/arp + статистики интерфейса
    while read -r ip mac; do
        [ -z "$ip" ] && continue
        # Получение счётчика байтов через iptables или nf_conntrack
        bytes=$(iptables -L FORWARD -v -n -x 2>/dev/null | grep "$ip" | awk '{sum+=$2} END{print sum+0}')
        echo "$ip $mac $bytes" >> "$tmpfile"
    done < <(arp -i "$NET_IF" -n 2>/dev/null | awk '/ether/{print $1,$4}')
}

get_client_bytes /tmp/bw_prev.txt

END_TIME=$(($(date +%s) + DURATION * 60))
ALERT_COUNT=0
TOTAL_BYTES=0

LOG "Запуск мониторинга пропускной способности..."
SPINNER_START "Мониторинг пропускной способности..."

while [ $(date +%s) -lt $END_TIME ]; do
    sleep "$INTERVAL"

    # Получение статистики на уровне интерфейса
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

    # Проверка по клиентам через дамп станций
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

    # Запись текущих показателей в журнал
    echo "[$TIMESTAMP] Всего: ${TOTAL_RATE} КБ/с (RX:${RX_RATE} TX:${TX_RATE})" >> "$LOG_FILE"

    # Проверка порога
    if [ "$TOTAL_RATE" -ge "$BW_THRESH" ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        echo "[$TIMESTAMP] ОПОВЕЩЕНИЕ: ${TOTAL_RATE} КБ/с превышает порог ${BW_THRESH} КБ/с" >> "$LOG_FILE"
        [ -n "$TOP_CLIENT" ] && echo "  Основной клиент: $TOP_CLIENT" >> "$LOG_FILE"
        LOG "Оповещение о пропускной способности: ${TOTAL_RATE} КБ/с"

        SPINNER_STOP
        PROMPT "⚠ ПРЕВЫШЕНИЕ ПРОПУСКНОЙ СПОСОБНОСТИ!

Текущая: ${TOTAL_RATE} КБ/с
Порог: ${BW_THRESH} КБ/с
RX: ${RX_RATE} КБ/с
TX: ${TX_RATE} КБ/с
$([ -n "$TOP_CLIENT" ] && echo "Основной: $TOP_CLIENT")

Оповещений: $ALERT_COUNT

Нажмите ОК для продолжения."
        SPINNER_START "Мониторинг..."
    fi
done

SPINNER_STOP
rm -f /tmp/bw_prev.txt

TOTAL_MB=$((TOTAL_BYTES / 1048576))

echo "============================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Всего данных: ${TOTAL_MB} МБ" >> "$LOG_FILE"
echo "Оповещений: $ALERT_COUNT" >> "$LOG_FILE"

PROMPT "МОНИТОРИНГ ЗАВЕРШЁН

Длительность: ${DURATION} мин
Всего данных: ${TOTAL_MB} МБ
Сработало оповещений: $ALERT_COUNT

Журнал сохранён в:
$LOG_FILE

Нажмите ОК для выхода."