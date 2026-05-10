#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Менеджер пакетов
# Author: NullSec
# Description: Управление пакетами opkg из UI Pager
# Category: nullsec/utility

LOOT_DIR="/mmc/nullsec/packagemanager"
mkdir -p "$LOOT_DIR"

PROMPT "МЕНЕДЖЕР ПАКЕТОВ

Управление пакетами OpenWrt
из UI Pager.

Особенности:
- Установка пакетов
- Удаление пакетов
- Обновление списков пакетов
- Поиск пакетов
- Просмотр установленных

Нажмите ОК для продолжения."

# Check opkg availability
if ! command -v opkg >/dev/null 2>&1; then
    ERROR_DIALOG "opkg не найден!

Этот payload требует
менеджер пакетов opkg."
    exit 1
fi

PROMPT "ОПЕРАЦИЯ С ПАКЕТАМИ:

1. Обновить списки пакетов
2. Установить пакет
3. Удалить пакет
4. Поиск пакетов
5. Список установленных
6. Проверить место на диске
7. Обновить все

Выберите операцию далее."

OPERATION=$(NUMBER_PICKER "Операция (1-7):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) OPERATION=1 ;; esac

case $OPERATION in
    1) # Update lists
        resp=$(CONFIRMATION_DIALOG "ОБНОВИТЬ СПИСКИ ПАКЕТОВ?

Это обновит базу данных
пакетов из настроенных
фидов.

Требует интернет.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Обновление списков пакетов..."
        UPDATE_OUT=$(opkg update 2>&1)
        RESULT=$?
        SPINNER_STOP

        if [ $RESULT -eq 0 ]; then
            FEED_COUNT=$(echo "$UPDATE_OUT" | grep -c "Downloading")
            PKG_COUNT=$(opkg list 2>/dev/null | wc -l)
            PROMPT "ОБНОВЛЕНИЕ ЗАВЕРШЕНО

Фидов обновлено: $FEED_COUNT
Пакетов доступно: $PKG_COUNT

Нажмите ОК для выхода."
        else
            ERROR_DIALOG "Update не удалась!

$(echo "$UPDATE_OUT" | tail -3)"
        fi
        ;;

    2) # Install package
        PKG_NAME=$(TEXT_PICKER "Имя пакета:" "nano")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        # Check if already установлен
        if opkg status "$PKG_NAME" 2>/dev/null | grep -q "Status.*установлен"; then
            PROMPT "$PKG_NAME уже
установлен!

Нажмите ОК для выхода."
            exit 0
        fi

        # Get package size
        PKG_SIZE=$(opkg info "$PKG_NAME" 2>/dev/null | grep "Size:" | awk '{print $2}')
        [ -z "$PKG_SIZE" ] && PKG_SIZE="unknown"

        resp=$(CONFIRMATION_DIALOG "УСТАНОВИТЬ $PKG_NAME?

Размер: $PKG_SIZE байт

Это скачает и установит
пакет.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Установка $PKG_NAME..."
        INSTALL_OUT=$(opkg install "$PKG_NAME" 2>&1)
        RESULT=$?
        SPINNER_STOP

        if [ $RESULT -eq 0 ]; then
            echo "$(date) | INSTALL | $PKG_NAME" >> "$LOOT_DIR/pkg_history.log"
            PROMPT "УСТАНОВЛЕНО!

$PKG_NAME установлен
успешно.

$(echo "$INSTALL_OUT" | tail -2)

Нажмите ОК для выхода."
        else
            ERROR_DIALOG "Install не удалась!

$(echo "$INSTALL_OUT" | tail -4)"
        fi
        ;;

    3) # Remove package
        PKG_NAME=$(TEXT_PICKER "Пакет для удаления:" "")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        if ! opkg status "$PKG_NAME" 2>/dev/null | grep -q "Status.*установлен"; then
            ERROR_DIALOG "$PKG_NAME не
установлен!"
            exit 1
        fi

        resp=$(CONFIRMATION_DIALOG "УДАЛИТЬ $PKG_NAME?

Это удалит пакет.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Удаление $PKG_NAME..."
        REMOVE_OUT=$(opkg remove "$PKG_NAME" 2>&1)
        RESULT=$?
        SPINNER_STOP

        if [ $RESULT -eq 0 ]; then
            echo "$(date) | REMOVE | $PKG_NAME" >> "$LOOT_DIR/pkg_history.log"
            PROMPT "УДАЛЕНО!

$PKG_NAME удален.

Нажмите ОК для выхода."
        else
            ERROR_DIALOG "Remove не удалась!

$(echo "$REMOVE_OUT" | tail -3)"
        fi
        ;;

    4) # Search
        SEARCH_TERM=$(TEXT_PICKER "Термин поиска:" "wifi")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        SPINNER_START "Поиск пакетов..."
        RESULTS=$(opkg list "*${SEARCH_TERM}*" 2>/dev/null | head -15)
        RESULT_COUNT=$(opkg list "*${SEARCH_TERM}*" 2>/dev/null | wc -l)
        SPINNER_STOP

        PROMPT "SEARCH: $SEARCH_TERM
Found: $RESULT_COUNT

$(echo "$RESULTS" | awk '{print $1}' | head -10)

$([ $RESULT_COUNT -gt 10 ] && echo "...and $((RESULT_COUNT-10)) more")

Press OK to exit."
        ;;

    5) # List установлен
        SPINNER_START "Listing packages..."
        INSTALLED=$(opkg list-установлен 2>/dev/null)
        INST_COUNT=$(echo "$INSTALLED" | wc -l)
        SPINNER_STOP

        # Save full list
        echo "$INSTALLED" > "$LOOT_DIR/установлен_$(date +%Y%m%d).txt"

        PROMPT "INSTALLED PACKAGES: $INST_COUNT

$(echo "$INSTALLED" | head -12 | awk '{print $1}')

...and $((INST_COUNT-12)) more

Full list saved to
$LOOT_DIR/

Press OK to exit."
        ;;

    6) # Disk space
        ROOT_FREE=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
        ROOT_USED=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}')
        TMP_FREE=$(df -h /tmp 2>/dev/null | tail -1 | awk '{print $4}')

        PROMPT "МЕСТО НА ДИСКЕ

Корень свободно: $ROOT_FREE ($ROOT_USED использовано)
Tmp свободно: $TMP_FREE

Устанавливайте на /mmc для
большего места.

Нажмите ОК для выхода."
        ;;

    7) # Upgrade all
        resp=$(CONFIRMATION_DIALOG "ОБНОВИТЬ ВСЕ ПАКЕТЫ?

ПРЕДУПРЕЖДЕНИЕ: Это может занять
много времени и использовать
значительную пропускную способность.

Обеспечьте стабильный интернет.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Обновление пакетов..."
        opkg update >/dev/null 2>&1
        UPGRADE_OUT=$(opkg upgrade 2>&1)
        UPGRADED=$(echo "$UPGRADE_OUT" | grep -c "Upgrading")
        SPINNER_STOP

        echo "$(date) | UPGRADE_ALL | $UPGRADED packages" >> "$LOOT_DIR/pkg_history.log"

        PROMPT "ОБНОВЛЕНИЕ ЗАВЕРШЕНО

Пакетов обновлено: $UPGRADED

Нажмите ОК для выхода."
        ;;
esac
