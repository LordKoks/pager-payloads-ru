#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Ротор MAC
# Author: bad-antics
# Description: Автоматически меняет MAC-адрес с настраиваемым интервалом
# Category: nullsec

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "РОТОР MAC
━━━━━━━━━━━━━━━━━━━━━━━━━
Автоматически меняет MAC-адрес
через интервалы, чтобы
избежать отслеживания.

Нажмите ОК для настройки."

CURRENT_MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null || echo "unknown")
PROMPT "Текущий MAC:\n$CURRENT_MAC"

INTERVAL=$(NUMBER_PICKER "Интервал смены (сек):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=60 ;; esac
[ $INTERVAL -lt 10 ] && INTERVAL=10

ROTATIONS=$(NUMBER_PICKER "Всего смен (0=∞):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ROTATIONS=10 ;; esac

resp=$(CONFIRMATION_DIALOG "Настройка смены MAC:
━━━━━━━━━━━━━━━━━━━━━━━━━
Интерфейс: $IFACE
Интервал: ${INTERVAL}s
Смен: $([ $ROTATIONS -eq 0 ] && echo Бесконечно || echo $ROTATIONS)

Запустить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

generate_mac() {
    printf '%02x:%02x:%02x:%02x:%02x:%02x'         $((RANDOM % 256 & 0xFE | 0x02))         $((RANDOM % 256)) $((RANDOM % 256))         $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

COUNT=0
while true; do
    NEW_MAC=$(generate_mac)
    ip link set $IFACE down 2>/dev/null
    ip link set $IFACE address "$NEW_MAC" 2>/dev/null
    ip link set $IFACE up 2>/dev/null
    COUNT=$((COUNT + 1))
    LOG "MAC #$COUNT: $NEW_MAC"
    
    [ $ROTATIONS -ne 0 ] && [ $COUNT -ge $ROTATIONS ] && break
    sleep "$INTERVAL"
done

FINAL_MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null)
PROMPT "СМЕНА MAC ЗАВЕРШЕНА
━━━━━━━━━━━━━━━━━━━━━━━━━
Смен: $COUNT
Текущий MAC: $FINAL_MAC
Оригинал: $CURRENT_MAC"
