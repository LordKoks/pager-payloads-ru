#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Название: Оповещение о деаутентификации
# Автор: NullSec
# Описание: Мониторинг фреймов деаутентификации и оповещение пользователя
# Категория: nullsec/alerts

LOOT_DIR="/mmc/nullsec/deauthalert"
mkdir -p "$LOOT_DIR"

PROMPT "ОПОВЕЩЕНИЕ О ДЕАУТЕНТИФИКАЦИИ

Мониторинг радиоэфира на
наличие фреймов деаутентификации
и оповещение при обнаружении
атак в реальном времени.

Возможности:
- Обнаружение фреймов деаутентификации
- Журналирование MAC-адресов источников
- Информация о канале и времени
- Настраиваемая чувствительность

Нажмите ОК для настройки."

# Обнаружение интерфейса мониторинга
MON_IF=""
for iface in wlan1mon wlan2mon wlan0mon; do
    [ -d "/sys/class/net/$iface" ] && MON_IF="$iface" && break
done
[ -z "$MON_IF" ] && { ERROR_DIALOG "Интерфейс мониторинга не найден!

Выполните: airmon-ng start wlan1"; exit 1; }

LOG "Интерфейс мониторинга: $MON_IF"

PROMPT "ЧУВСТВИТЕЛЬНОСТЬ:

1. Низкая (10+ деаутентификаций/мин)
2. Средняя (5+ деаутентификаций/мин)
3. Высокая (1+ деаутентификаций/мин)

Выберите порог далее."

SENSITIVITY=$(NUMBER_PICKER "Чувствительность (1-3):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SENSITIVITY=2 ;; esac
[ "$SENSITIVITY" -lt 1 ] && SENSITIVITY=1
[ "$SENSITIVITY" -gt 3 ] && SENSITIVITY=3

case $SENSITIVITY in
    1) THRESHOLD=10 ;;
    2) THRESHOLD=5 ;;
    3) THRESHOLD=1 ;;
esac

DURATION=$(NUMBER_PICKER "Мониторинг (минут):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 1440 ] && DURATION=1440

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ МОНИТОРИНГ?

Интерфейс: $MON_IF
Порог: $THRESHOLD деаутентификаций/мин
Длительность: ${DURATION} мин

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG_FILE="$LOOT_DIR/deauth_$(date +%Y%m%d_%H%M).log"
echo "=== ЖУРНАЛ ОПОВЕЩЕНИЙ О ДЕАУТЕНТИФИКАЦИИ ===" > "$LOG_FILE"
echo "Начало: $(date)" >> "$LOG_FILE"
echo "Порог: $THRESHOLD деаутентификаций/мин" >> "$LOG_FILE"
echo "========================" >> "$LOG_FILE"

END_TIME=$(($(date +%s) + DURATION * 60))
TOTAL_DEAUTHS=0
ALERT_COUNT=0

LOG "Мониторинг атак деаутентификации..."
SPINNER_START "Сканирование фреймов деаутентификации..."

while [ $(date +%s) -lt $END_TIME ]; do
    DEAUTH_COUNT=0

    for CH in 1 6 11 2 3 4 5 7 8 9 10; do
        [ $(date +%s) -ge $END_TIME ] && break
        iwconfig "$MON_IF" channel "$CH" 2>/dev/null

        # Захват фреймов деаутентификации/отключения (тип 0 подтип 12 = деаутентификация, подтип 10 = отключение)
        HITS=$(timeout 2 tcpdump -i "$MON_IF" -c 100 -e 2>/dev/null | \
            grep -ci "deauthentication\|disassoc" 2>/dev/null || echo 0)
        DEAUTH_COUNT=$((DEAUTH_COUNT + HITS))

        if [ "$HITS" -gt 0 ]; then
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            # Извлечение MAC-адресов источников из фреймов деаутентификации
            SRC_MAC=$(timeout 1 tcpdump -i "$MON_IF" -c 5 -e 2>/dev/null | \
                grep -i "deauth" | awk '{print $2}' | head -1)
            [ -z "$SRC_MAC" ] && SRC_MAC="неизвестно"
            echo "[$TIMESTAMP] Кан:$CH Ист:$SRC_MAC Кол-во:$HITS" >> "$LOG_FILE"
        fi
    done

    TOTAL_DEAUTHS=$((TOTAL_DEAUTHS + DEAUTH_COUNT))

    if [ "$DEAUTH_COUNT" -ge "$THRESHOLD" ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        SPINNER_STOP
        LOG "ОПОВЕЩЕНИЕ: Обнаружено $DEAUTH_COUNT деаутентификаций!"
        echo "[ОПОВЕЩЕНИЕ $(date '+%H:%M:%S')] $DEAUTH_COUNT деаутентификаций за проход" >> "$LOG_FILE"

        PROMPT "⚠ ОБНАРУЖЕНА ДЕАУТЕНТИФИКАЦИЯ!

Найдено $DEAUTH_COUNT фреймов
деаутентификации за последний
проход.

Всего оповещений: $ALERT_COUNT
Всего деаутентификаций: $TOTAL_DEAUTHS

Нажмите ОК для продолжения
мониторинга."
        SPINNER_START "Мониторинг..."
    fi

    sleep 1
done

SPINNER_STOP

echo "========================" >> "$LOG_FILE"
echo "Завершено: $(date)" >> "$LOG_FILE"
echo "Всего деаутентификаций: $TOTAL_DEAUTHS" >> "$LOG_FILE"
echo "Всего оповещений: $ALERT_COUNT" >> "$LOG_FILE"

PROMPT "МОНИТОРИНГ ЗАВЕРШЁН

Длительность: ${DURATION} мин
Всего деаутентификаций: $TOTAL_DEAUTHS
Сработало оповещений: $ALERT_COUNT

Журнал сохранён в:
$LOG_FILE

Нажмите ОК для выхода."