#!/bin/bash
# Название: Оповещение о вторжении
# Автор: NullSec
# Описание: Сетевое обнаружение вторжений для сканирования портов, ARP-спуфинга и подозрительного трафика
# Категория: nullsec/alerts

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/intrusionalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О ВТОРЖЕНИИ

Облегчённая сетевая IDS
для WiFi Pineapple.

Обнаруживает:
- Сканирование портов
- Атаки ARP-спуфинга
- Попытки SYN-флуда
- Необычные шаблоны трафика

Нажмите ОК для настройки."

# Определение сетевого интерфейса
NET_IF=""
for iface in br-lan eth0 $IFACE; do
    [ -d "/sys/class/net/$iface" ] && NET_IF="$iface" && break
done
[ -z "$NET_IF" ] && { ERROR_DIALOG "Сетевой интерфейс не найден!"; exit 1; }

LOG "Сетевой интерфейс: $NET_IF"

PROMPT "МОДУЛИ ОБНАРУЖЕНИЯ:

Все модули включены:
- Обнаружение сканирования портов
- Обнаружение ARP-спуфинга
- Обнаружение SYN-флуда
- Обнаружение аномалий DNS

Нажмите ОК для установки длительности."

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 30)
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

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/ids_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О ВТОРЖЕНИЯХ ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "Интерфейс: $NET_IF" >> "$LOG_FILE"
echo "===========================" >> "$LOG_FILE"

# Снятие базового уровня ARP
arp -i "$NET_IF" -n 2>/dev/null | awk '/ether/{print $1,$4}' | sort > /tmp/ids_arp_base.txt

END_TIME=$(($(date +%s) + DURATION * 60))
ALERT_COUNT=0
CYCLE=0

LOG "Запуск мониторинга IDS..."
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
        echo "[$TIMESTAMP] СКАНИРОВАНИЕ_ПОРТОВ от $SRC_IP ($SYN_COUNT SYN)" >> "$LOG_FILE"
        LOG "Сканирование портов: $SRC_IP"
    fi

    # --- Обнаружение ARP-спуфинга ---
    arp -i "$NET_IF" -n 2>/dev/null | awk '/ether/{print $1,$4}' | sort > /tmp/ids_arp_now.txt
    while read -r ip mac; do
        OLD_MAC=$(grep "^$ip " /tmp/ids_arp_base.txt 2>/dev/null | awk '{print $2}')
        if [ -n "$OLD_MAC" ] && [ "$OLD_MAC" != "$mac" ]; then
            ALERT_COUNT=$((ALERT_COUNT + 1))
            ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
            echo "[$TIMESTAMP] ARP_СПУФИНГ IP:$ip было:$OLD_MAC стало:$mac" >> "$LOG_FILE"
            LOG "ARP-спуфинг: $ip"
        fi
    done < /tmp/ids_arp_now.txt
    cp /tmp/ids_arp_now.txt /tmp/ids_arp_base.txt

    # --- Обнаружение SYN-флуда ---
    FLOOD=$(timeout 3 tcpdump -i "$NET_IF" -c 500 'tcp[tcpflags] == tcp-syn' 2>/dev/null | wc -l)
    if [ "$FLOOD" -ge 100 ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
        echo "[$TIMESTAMP] SYN_ФЛУД $FLOOD SYN за 3с" >> "$LOG_FILE"
        LOG "Обнаружен SYN-флуд!"
    fi

    # --- Обнаружение аномалий DNS ---
    DNS_COUNT=$(timeout 3 tcpdump -i "$NET_IF" -c 200 'port 53' 2>/dev/null | wc -l)
    if [ "$DNS_COUNT" -ge 150 ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        ALERTS_THIS_CYCLE=$((ALERTS_THIS_CYCLE + 1))
        echo "[$TIMESTAMP] АНОМАЛИЯ_DNS $DNS_COUNT запросов за 3с" >> "$LOG_FILE"
    fi

    # Показать оповещение, если что-то сработало
    if [ "$ALERTS_THIS_CYCLE" -gt 0 ]; then
        SPINNER_STOP
        PROMPT "⚠ ОБНАРУЖЕНО ВТОРЖЕНИЕ!

Оповещений в этом цикле: $ALERTS_THIS_CYCLE
Всего оповещений: $ALERT_COUNT

Проверьте журнал для подробностей.

Нажмите ОК для продолжения."
        SPINNER_START "Мониторинг..."
    fi

    sleep 5
done

SPINNER_STOP
rm -f /tmp/ids_arp_base.txt /tmp/ids_arp_now.txt

echo "===========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Всего оповещений: $ALERT_COUNT" >> "$LOG_FILE"
echo "Выполнено циклов: $CYCLE" >> "$LOG_FILE"

PROMPT "МОНИТОРИНГ IDS ЗАВЕРШЁН

Длительность: ${DURATION} мин
Всего оповещений: $ALERT_COUNT
Циклов сканирования: $CYCLE

Журнал сохранён в:
$LOG_FILE

Нажмите ОК для выхода."