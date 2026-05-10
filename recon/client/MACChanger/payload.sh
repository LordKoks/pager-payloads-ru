#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Смена MAC
# Author: NullSec
# Description: Меняет MAC-адрес на интерфейсах с несколькими режимами
# Category: nullsec/utility

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/macchanger"
mkdir -p "$LOOT_DIR"

PROMPT "СМЕНА MAC

Меняет MAC-адреса на
сетевых интерфейсах.

Режимы:
- Случайный MAC
- Конкретный MAC
- Подмена производителя
- Восстановить оригинал

Нажмите ОК для настройки."

# Список доступных интерфейсов
IFACE_LIST=""
IFACE_COUNT=0
for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
    CURRENT_MAC=$(cat /sys/class/net/$iface/address 2>/dev/null)
    IFACE_LIST="${IFACE_LIST}${iface}: ${CURRENT_MAC}\n"
    IFACE_COUNT=$((IFACE_COUNT + 1))
done

[ $IFACE_COUNT -eq 0 ] && { ERROR_DIALOG "Интерфейсы не найдены!"; exit 1; }

PROMPT "ИНТЕРФЕЙСЫ:

$(echo -e "$IFACE_LIST")
Всего: $IFACE_COUNT

Нажмите ОК, чтобы
выбрать интерфейс."

TARGET_IFACE=$(TEXT_PICKER "Интерфейс:" "$IFACE")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TARGET_IFACE="$IFACE" ;; esac

if [ ! -d "/sys/class/net/$TARGET_IFACE" ]; then
    ERROR_DIALOG "Интерфейс $TARGET_IFACE
не найден!"
    exit 1
fi

ORIGINAL_MAC=$(cat /sys/class/net/$TARGET_IFACE/address 2>/dev/null)

PROMPT "РЕЖИМ СМЕНЫ:

1. Случайный MAC
2. Конкретный MAC
3. Подмена производителя
4. Восстановить оригинал

Текущий MAC:
$ORIGINAL_MAC

Выберите режим." 

CHANGE_MODE=$(NUMBER_PICKER "Режим (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CHANGE_MODE=1 ;; esac

# Генерация нового MAC в зависимости от режима
NEW_MAC=""
case $CHANGE_MODE in
    1) # Случайный MAC
        NEW_MAC=$(printf '%02x:%02x:%02x:%02x:%02x:%02x' \
            $((RANDOM%256 & 0xFE | 0x02)) $((RANDOM%256)) $((RANDOM%256)) \
            $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        ;;
    2) # Конкретный MAC
        NEW_MAC=$(TEXT_PICKER "Новый MAC:" "AA:BB:CC:DD:EE:FF")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac
        if ! echo "$NEW_MAC" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
            ERROR_DIALOG "Неверный формат MAC!

Используйте: XX:XX:XX:XX:XX:XX"
            exit 1
        fi
        ;;
    3) # Подмена производителя
        PROMPT "ПОДМЕНА ПРОИЗВОДИТЕЛЯ:

1. Apple (iPhone)
2. Samsung Galaxy
3. Google Pixel
4. Intel laptop
5. Cisco device
6. Случайный производитель

Выберите производителя." 
        VENDOR=$(NUMBER_PICKER "Производитель (1-6):" 1)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) VENDOR=1 ;; esac
        case $VENDOR in
            1) OUI="F0:D4:F7" ;; # Apple
            2) OUI="AC:5F:3E" ;; # Samsung
            3) OUI="3C:28:6D" ;; # Google
            4) OUI="A4:34:D9" ;; # Intel
            5) OUI="00:1A:2B" ;; # Cisco
            *) OUI=$(printf '%02x:%02x:%02x' $((RANDOM%256 & 0xFE)) $((RANDOM%256)) $((RANDOM%256))) ;;
        esac
        NEW_MAC=$(printf '%s:%02x:%02x:%02x' "$OUI" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        ;;
    4) # Восстановление оригинала
        if [ -f "$LOOT_DIR/original_${TARGET_IFACE}.mac" ]; then
            NEW_MAC=$(cat "$LOOT_DIR/original_${TARGET_IFACE}.mac")
        else
            ERROR_DIALOG "Нет сохраненного оригинального MAC
для $TARGET_IFACE!"
            exit 1
        fi
        ;;
esac

resp=$(CONFIRMATION_DIALOG "СМЕНИТЬ MAC?

Интерфейс: $TARGET_IFACE
Текущий:   $ORIGINAL_MAC
Новый MAC: $NEW_MAC

Интерфейс будет
коротко отключен.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# Сохранить оригинальный MAC
echo "$ORIGINAL_MAC" > "$LOOT_DIR/original_${TARGET_IFACE}.mac"

LOG "Меняю MAC на $TARGET_IFACE..."
SPINNER_START "Меняю MAC-адрес..."

# Опустить интерфейс, сменить MAC, поднять обратно
ip link set "$TARGET_IFACE" down 2>/dev/null
sleep 1

if command -v macchanger >/dev/null 2>&1; then
    macchanger -m "$NEW_MAC" "$TARGET_IFACE" 2>/dev/null
else
    ip link set "$TARGET_IFACE" address "$NEW_MAC" 2>/dev/null
fi

RESULT=$?
ip link set "$TARGET_IFACE" up 2>/dev/null
sleep 2

SPINNER_STOP

VERIFY_MAC=$(cat /sys/class/net/$TARGET_IFACE/address 2>/dev/null)

# Запись изменений в лог
echo "$(date) | $TARGET_IFACE | $ORIGINAL_MAC -> $VERIFY_MAC" >> "$LOOT_DIR/mac_history.log"

if [ "$VERIFY_MAC" = "$NEW_MAC" ] || [ "$VERIFY_MAC" = "$(echo "$NEW_MAC" | tr 'A-F' 'a-f')" ]; then
    PROMPT "MAC ИЗМЕНЕН!

Интерфейс: $TARGET_IFACE
Старый MAC: $ORIGINAL_MAC
Новый MAC: $VERIFY_MAC

Оригинал сохранен для
восстановления. Лог обновлен.

Нажмите ОК для выхода."
else
    ERROR_DIALOG "Возможно, смена MAC не удалась!

Ожидалось: $NEW_MAC
Получено:  $VERIFY_MAC

Некоторые драйверы ограничивают
смену MAC."
fi
