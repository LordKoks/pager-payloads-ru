#!/bin/bash
# Название: Оповещение о клиентах
# Автор: NullSec
# Описание: Оповещает при подключении новых клиентов к точке доступа Pineapple
# Категория: nullsec/alerts

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/clientalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О КЛИЕНТАХ

Мониторинг новых клиентов,
подключающихся к вашей
точке доступа.

Возможности:
- Обнаружение подключений
- Журналирование MAC-адресов
- Определение производителя
- Оповещения в реальном времени

Нажмите ОК для настройки."

# Проверка интерфейса точки доступа
AP_IF=""
for iface in $IFACE br-lan; do
    [ -d "/sys/class/net/$iface" ] && AP_IF="$iface" && break
done
[ -z "$AP_IF" ] && { ERROR_DIALOG "Интерфейс точки доступа не найден!

Убедитесь, что точка доступа
Pineapple запущена."; exit 1; }

LOG "Интерфейс точки доступа: $AP_IF"

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 30)
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
Период опроса: ${POLL_RATE} с

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/clients_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О КЛИЕНТАХ ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "Интерфейс: $AP_IF" >> "$LOG_FILE"
echo "========================" >> "$LOG_FILE"

# Функция определения производителя
get_vendor() {
    local mac_prefix=$(echo "$1" | tr -d ':' | head -c 6 | tr 'a-f' 'A-F')
    local vendor=""
    if [ -f /usr/share/ieee-oui.txt ]; then
        vendor=$(grep -i "$mac_prefix" /usr/share/ieee-oui.txt 2>/dev/null | head -1 | cut -d')' -f2 | sed 's/^[[:space:]]*//')
    elif [ -f /etc/oui.txt ]; then
        vendor=$(grep -i "$mac_prefix" /etc/oui.txt 2>/dev/null | head -1 | awk -F'\t' '{print $NF}')
    fi
    [ -z "$vendor" ] && vendor="Неизвестно"
    echo "$vendor" | head -c 20
}

# Снимок текущих клиентов
arp -i "$AP_IF" -n 2>/dev/null | awk '/ether/{print $4}' | sort -u > /tmp/ca_known.txt
iw dev "$AP_IF" station dump 2>/dev/null | awk '/Station/{print $2}' | sort -u >> /tmp/ca_known.txt
sort -u /tmp/ca_known.txt -o /tmp/ca_known.txt

KNOWN=$(wc -l < /tmp/ca_known.txt)
NEW_COUNT=0
END_TIME=$(($(date +%s) + DURATION * 60))

LOG "Мониторинг клиентов (изначально: ${KNOWN})..."
SPINNER_START "Отслеживание новых клиентов..."

while [ $(date +%s) -lt $END_TIME ]; do
    sleep "$POLL_RATE"

    # Получение текущих клиентов из ARP и дампа станций
    arp -i "$AP_IF" -n 2>/dev/null | awk '/ether/{print $4}' | sort -u > /tmp/ca_current.txt
    iw dev "$AP_IF" station dump 2>/dev/null | awk '/Station/{print $2}' | sort -u >> /tmp/ca_current.txt
    sort -u /tmp/ca_current.txt -o /tmp/ca_current.txt

    # Поиск новых клиентов
    NEW_MACS=$(comm -13 /tmp/ca_known.txt /tmp/ca_current.txt 2>/dev/null)

    if [ -n "$NEW_MACS" ]; then
        while IFS= read -r MAC; do
            [ -z "$MAC" ] && continue
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            VENDOR=$(get_vendor "$MAC")
            IP=$(arp -n 2>/dev/null | grep -i "$MAC" | awk '{print $1}' | head -1)
            [ -z "$IP" ] && IP="ожидание"

            NEW_COUNT=$((NEW_COUNT + 1))
            echo "[$TIMESTAMP] НОВЫЙ: $MAC ($VENDOR) IP:$IP" >> "$LOG_FILE"
            LOG "Новый клиент: $MAC"

            SPINNER_STOP
            PROMPT "⚠ НОВЫЙ КЛИЕНТ!

MAC: $MAC
Производитель: $VENDOR
IP: $IP
Время: $TIMESTAMP

Всего новых: $NEW_COUNT

Нажмите ОК для продолжения."
            SPINNER_START "Отслеживание..."
        done <<< "$NEW_MACS"

        cp /tmp/ca_current.txt /tmp/ca_known.txt
    fi
done

SPINNER_STOP
rm -f /tmp/ca_known.txt /tmp/ca_current.txt

echo "========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Новых клиентов: $NEW_COUNT" >> "$LOG_FILE"

PROMPT "ОПОВЕЩЕНИЕ О КЛИЕНТАХ ЗАВЕРШЕНО

Длительность: ${DURATION} мин
Изначально клиентов: $KNOWN
Новых клиентов: $NEW_COUNT

Журнал сохранён в:
$LOG_FILE

Нажмите ОК для выхода."