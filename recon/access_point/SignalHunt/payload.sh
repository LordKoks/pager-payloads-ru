#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Охота за сигналом
# Author: bad-antics
# Description: Игра на поиск самого сильного WiFi-сигнала
# Category: nullsec

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ОХОТА ЗА СИГНАЛОМ
━━━━━━━━━━━━━━━━━━━━━━━━━
Найди источник самого
сильного WiFi-сигнала!

Ходи с устройством и
отслеживай уровень сигнала
в реальном времени.

Нажми OK для запуска."

MONITOR_IF=""
for iface in wlan1mon wlan2mon wlan1 $IFACE; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "WiFi-интерфейс не найден!"; exit 1; }

ROUNDS=$(NUMBER_PICKER "Количество раундов (по 30 сек):" 5)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ROUNDS=5 ;; esac

BEST_SIGNAL=-100
BEST_ROUND=0

for ROUND in $(seq 1 $ROUNDS); do
    rm -f /tmp/sig_hunt*
    timeout 5 airodump-ng "$MONITOR_IF" -w /tmp/sig_hunt --output-format csv 2>/dev/null &
    sleep 5
    killall airodump-ng 2>/dev/null
    
    STRONGEST=-100
    STRONGEST_NAME=""
    while IFS=',' read -r bssid x1 x2 x3 x4 x5 x6 x7 power x8 x9 x10 x11 essid rest; do
        bssid=$(echo "$bssid" | tr -d ' ')
        [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
        power=$(echo "$power" | tr -d ' ')
        [ -z "$power" ] && continue
        essid=$(echo "$essid" | tr -d ' ' | head -c 12)
        if [ "$power" -gt "$STRONGEST" ] 2>/dev/null; then
            STRONGEST=$power
            STRONGEST_NAME=$essid
        fi
    done < /tmp/sig_hunt-01.csv
    
    if [ "$STRONGEST" -gt "$BEST_SIGNAL" ]; then
        BEST_SIGNAL=$STRONGEST
        BEST_ROUND=$ROUND
    fi
    
    BAR_LEN=$(( (STRONGEST + 100) / 5 ))
    [ $BAR_LEN -lt 0 ] && BAR_LEN=0
    [ $BAR_LEN -gt 20 ] && BAR_LEN=20
    BAR=$(printf '█%.0s' $(seq 1 $BAR_LEN))
    
    PROMPT "РАУНД $ROUND/$ROUNDS
━━━━━━━━━━━━━━━━━━━━━━━━━
Самый сильный: $STRONGEST_NAME
Сигнал: ${STRONGEST} dBm
${BAR}

Рекорд: ${BEST_SIGNAL} dBm (R$BEST_ROUND)
━━━━━━━━━━━━━━━━━━━━━━━━━
Ходи по территории!
Следующий раунд через 5 сек..."
    
    [ $ROUND -lt $ROUNDS ] && sleep 25
done

PROMPT "ИГРА ЗАВЕРШЕНА!
━━━━━━━━━━━━━━━━━━━━━━━━━
Лучший сигнал:
${BEST_SIGNAL} dBm
в раунде $BEST_ROUND

Счёт: $(( (BEST_SIGNAL + 100) * 10 )) / 1000"