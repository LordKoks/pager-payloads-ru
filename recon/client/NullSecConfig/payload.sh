#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
#═══════════════════════════════════════════════════════════════════════════════
# Менеджер Конфигурации NullSec
# Разработано: bad-antics
# 
# Настройка параметров NullSec, включая быстрый сброс, производительность и т.д.
#═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR="/mmc/nullsec"
CONFIG_FILE="$CONFIG_DIR/config.sh"
mkdir -p "$CONFIG_DIR"

# Default config
[ ! -f "$CONFIG_FILE" ] && cat > "$CONFIG_FILE" << 'DEFAULTS'
# Конфигурация NullSec - Измените значения ниже
export NULLSEC_QUICK_DISMISS=1      # 1=включено (лево/право очищает все подсказки)
export NULLSEC_SCAN_TIME=15         # Длительность сканирования по умолчанию в секундах
export NULLSEC_PERFORMANCE_MODE=0   # 1=быстрый режим (уменьшенные таймауты)
export NULLSEC_LOOT_PATH="/mmc/nullsec"
export NULLSEC_AUTO_CLEANUP=1       # 1=очистка временных файлов после payload
DEFAULTS

# Load current config
source "$CONFIG_FILE" 2>/dev/null

PROMPT "╔╗╔╦ ╦╦  ╦  ╔═╗╔═╗╔═╗
║║║║ ║║  ║  ╚═╗║╣ ║  
╝╚╝╚═╝╩═╝╩═╝╚═╝╚═╝╚═╝
━━━━━━━━━━━━━━━━━━━━━━━━━
Менеджер Конфигурации

Настройте свой опыт
NullSec.

━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"

PROMPT "МЕНЮ НАСТРОЕК:

1. Быстрый Сброс
   (Сейчас: $([ $NULLSEC_QUICK_DISMISS -eq 1 ] && echo ВКЛ || echo ВЫКЛ))

2. Режим Производительности
   (Сейчас: $([ $NULLSEC_PERFORMANCE_MODE -eq 1 ] && echo БЫСТРЫЙ || echo НОРМАЛЬНЫЙ))

3. Длительность Сканирования
   (Сейчас: ${NULLSEC_SCAN_TIME}с)

4. Просмотр Всех Настроек

5. Сброс к Умолчанию"

CHOICE=$(NUMBER_PICKER "Опция (1-5):" 1)

case $CHOICE in
    1) # Quick Dismiss toggle
        if [ $NULLSEC_QUICK_DISMISS -eq 1 ]; then
            sed -i 's/NULLSEC_QUICK_DISMISS=1/NULLSEC_QUICK_DISMISS=0/' "$CONFIG_FILE"
            PROMPT "Быстрый Сброс: ВЫКЛ

Подсказки теперь требуют
индивидуального подтверждения."
        else
            sed -i 's/NULLSEC_QUICK_DISMISS=0/NULLSEC_QUICK_DISMISS=1/' "$CONFIG_FILE"
            PROMPT "Быстрый Сброс: ВКЛ

Используйте ЛЕВО/ПРАВО для
очистки нескольких подсказок сразу.

Нажмите ВЫБОР для подтверждения
индивидуальных подсказок."
        fi
        ;;
    2) # Performance Mode
        if [ $NULLSEC_PERFORMANCE_MODE -eq 1 ]; then
            sed -i 's/NULLSEC_PERFORMANCE_MODE=1/NULLSEC_PERFORMANCE_MODE=0/' "$CONFIG_FILE"
            PROMPT "Режим Производительности: НОРМАЛЬНЫЙ

Стандартные таймауты и
задержки восстановлены."
        else
            sed -i 's/NULLSEC_PERFORMANCE_MODE=0/NULLSEC_PERFORMANCE_MODE=1/' "$CONFIG_FILE"
            PROMPT "Режим Производительности: БЫСТРЫЙ

Уменьшенные таймауты для
быстрого выполнения.

Примечание: Может уменьшить
точность сканирования."
        fi
        ;;
    3) # Scan Duration
        NEW_TIME=$(NUMBER_PICKER "Время сканирования (5-60):" $NULLSEC_SCAN_TIME)
        [ "$NEW_TIME" -lt 5 ] && NEW_TIME=5
        [ "$NEW_TIME" -gt 60 ] && NEW_TIME=60
        sed -i "s/NULLSEC_SCAN_TIME=.*/NULLSEC_SCAN_TIME=$NEW_TIME/" "$CONFIG_FILE"
        PROMPT "Длительность Сканирования: ${NEW_TIME}с

Сканирования сети теперь
будут выполняться $NEW_TIME секунд."
        ;;
    4) # View settings
        PROMPT "ТЕКУЩИЕ НАСТРОЙКИ:
━━━━━━━━━━━━━━━━━━━━━━━━━
Быстрый Сброс: $([ $NULLSEC_QUICK_DISMISS -eq 1 ] && echo ВКЛ || echo ВЫКЛ)
Производительность: $([ $NULLSEC_PERFORMANCE_MODE -eq 1 ] && echo БЫСТРАЯ || echo НОРМАЛЬНАЯ)
Время Сканирования: ${NULLSEC_SCAN_TIME}с
Путь к Лугу: $NULLSEC_LOOT_PATH
Авто Очистка: $([ $NULLSEC_AUTO_CLEANUP -eq 1 ] && echo ВКЛ || echo ВЫКЛ)
━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    5) # Reset
        CONFIRMATION_DIALOG "Сбросить все настройки
к умолчаниям?

Это нельзя отменить."
        if [ $? -eq 0 ]; then
            cat > "$CONFIG_FILE" << 'DEFAULTS'
# NullSec Configuration
export NULLSEC_QUICK_DISMISS=1
export NULLSEC_SCAN_TIME=15
export NULLSEC_PERFORMANCE_MODE=0
export NULLSEC_LOOT_PATH="/mmc/nullsec"
export NULLSEC_AUTO_CLEANUP=1
DEFAULTS
            PROMPT "Настройки сброшены к
умолчаниям."
        fi
        ;;
esac

PROMPT "КОНФИГ СОХРАНЕН
━━━━━━━━━━━━━━━━━━━━━━━━━
Настройки будут применены ко
всем NullSec payload'ам.

━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
