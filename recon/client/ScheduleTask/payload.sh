#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Планировщик задач
# Author: NullSec
# Description: Планирование запуска пейлоудов и команд по расписанию через cron
# Category: nullsec/utility

LOOT_DIR="/mmc/nullsec/scheduletask"
mkdir -p "$LOOT_DIR"

PROMPT "ПЛАНИРОВЩИК ЗАДАЧ

Позволяет запланировать запуск
пейлоудов и команд в определённое время.

Возможности:
- Одноразовый запуск
- Повторяющиеся задачи
- Планирование пейлоудов
- Просмотр и удаление задач
- Журнал выполнения

Нажми OK для настройки."

# Проверка наличия crontab
if ! command -v crontab >/dev/null 2>&1; then
    ERROR_DIALOG "crontab не найден!

Установи командой:
opkg install busybox"
    exit 1
fi

PROMPT "ВЫБЕРИ ДЕЙСТВИЕ:

1. Добавить новую задачу
2. Просмотреть задачи
3. Удалить задачу
4. Запланировать пейлоуд
5. Просмотреть журнал выполнения

Выбери операцию:"

OPERATION=$(NUMBER_PICKER "Операция (1-5):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) OPERATION=1 ;; esac

case $OPERATION in
    1) # Добавить новую задачу
        PROMPT "ТИП РАСПИСАНИЯ:

1. Запуск при загрузке
2. Каждые N минут
3. Каждый час
4. Ежедневно в указанный час
5. Собственное cron-выражение

Выбери тип:"

        SCHED_TYPE=$(NUMBER_PICKER "Тип (1-5):" 2)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SCHED_TYPE=2 ;; esac

        COMMAND=$(TEXT_PICKER "Команда:" "/bin/sh /path/to/script.sh")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        case $SCHED_TYPE in
            1)
                CRON_EXPR="@reboot"
                SCHED_LABEL="При загрузке"
                ;;
            2)
                INTERVAL=$(NUMBER_PICKER "Интервал (минуты):" 30)
                case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) INTERVAL=30 ;; esac
                CRON_EXPR="*/$INTERVAL * * * *"
                SCHED_LABEL="Каждые ${INTERVAL} мин"
                ;;
            3)
                MINUTE=$(NUMBER_PICKER "Минута часа:" 0)
                case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MINUTE=0 ;; esac
                CRON_EXPR="$MINUTE * * * *"
                SCHED_LABEL="Каждый час в :${MINUTE}"
                ;;
            4)
                HOUR=$(NUMBER_PICKER "Час (0-23):" 12)
                case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) HOUR=12 ;; esac
                CRON_EXPR="0 $HOUR * * *"
                SCHED_LABEL="Ежедневно в ${HOUR}:00"
                ;;
            5)
                CRON_EXPR=$(TEXT_PICKER "Cron-выражение:" "*/5 * * * *")
                case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac
                SCHED_LABEL="Пользовательское"
                ;;
        esac

        LOG_CMD="$COMMAND >> $LOOT_DIR/exec.log 2>&1"
        CRON_LINE="$CRON_EXPR $LOG_CMD # NULLSEC_TASK"

        resp=$(CONFIRMATION_DIALOG "ДОБАВИТЬ ЗАДАЧУ?

Расписание: $SCHED_LABEL
Выражение: $CRON_EXPR
Команда: $(echo "$COMMAND" | head -c 40)

Подтверждаешь?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Добавление задачи..."

        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
        RESULT=$?

        SPINNER_STOP

        if [ $RESULT -eq 0 ]; then
            echo "$(date) | ДОБАВЛЕНО | $SCHED_LABEL | $COMMAND" >> "$LOOT_DIR/tasks.log"
            LOG "Задача запланирована: $SCHED_LABEL"
            PROMPT "ЗАДАЧА УСПЕШНО ЗАПЛАНИРОВАНА!

Расписание: $SCHED_LABEL
Команда добавлена в cron.

Нажми OK для выхода."
        else
            ERROR_DIALOG "Не удалось добавить задачу!

Проверь работу cron."
        fi
        ;;

    2) # Просмотр задач
        SPINNER_START "Чтение расписания..."
        TASKS=$(crontab -l 2>/dev/null | grep "NULLSEC_TASK")
        TASK_COUNT=$(echo "$TASKS" | grep -c "NULLSEC_TASK")
        [ -z "$TASKS" ] && TASK_COUNT=0
        SPINNER_STOP

        if [ $TASK_COUNT -eq 0 ]; then
            PROMPT "ЗАДАЧ НЕ НАЙДЕНО

В crontab нет задач NullSec.

Нажми OK для выхода."
        else
            PROMPT "ЗАПЛАНИРОВАННЫЕ ЗАДАЧИ: $TASK_COUNT

$(echo "$TASKS" | sed 's/ # NULLSEC_TASK//' | head -8)

Нажми OK для выхода."
        fi
        ;;

    3) # Удаление задачи
        TASKS=$(crontab -l 2>/dev/null | grep "NULLSEC_TASK")
        TASK_COUNT=$(echo "$TASKS" | grep -c "NULLSEC_TASK")
        [ -z "$TASKS" ] && TASK_COUNT=0

        if [ $TASK_COUNT -eq 0 ]; then
            PROMPT "Нет задач для удаления.

Нажми OK для выхода."
            exit 0
        fi

        PROMPT "ОПЦИИ УДАЛЕНИЯ:

1. Удалить все задачи NullSec
2. Удалить последнюю задачу

Найдено задач: $TASK_COUNT

Выбери действие:"

        REMOVE_OPT=$(NUMBER_PICKER "Действие (1-2):" 1)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        resp=$(CONFIRMATION_DIALOG "УДАЛИТЬ ЗАДАЧИ?

Это действие нельзя отменить.

Подтверждаешь?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Удаление задач..."
        if [ "$REMOVE_OPT" = "1" ]; then
            crontab -l 2>/dev/null | grep -v "NULLSEC_TASK" | crontab -
        else
            crontab -l 2>/dev/null | sed '$ {/NULLSEC_TASK/d}' | crontab -
        fi
        SPINNER_STOP

        echo "$(date) | УДАЛЕНО | вариант $REMOVE_OPT" >> "$LOOT_DIR/tasks.log"
        PROMPT "ЗАДАЧИ УДАЛЕНЫ

Нажми OK для выхода."
        ;;

    4) # Запланировать пейлоуд
        PROMPT "ЗАПУСТИТЬ ПЕЙЛОУД ПО РАСПИСАНИЮ

Выбери пейлоуд из папки
/mmc/payloads/ для 
запланированного запуска.

Нажми OK для продолжения."

        PAYLOADS=$(ls /mmc/payloads/ 2>/dev/null | head -10)
        [ -z "$PAYLOADS" ] && { ERROR_DIALOG "Пейлоуды не найдены в /mmc/payloads/"; exit 1; }

        PAYLOAD_NAME=$(TEXT_PICKER "Название папки пейлоуда:" "$(echo "$PAYLOADS" | head -1)")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        PAYLOAD_PATH="/mmc/payloads/$PAYLOAD_NAME/payload.sh"
        [ ! -f "$PAYLOAD_PATH" ] && { ERROR_DIALOG "Пейлоуд не найден: $PAYLOAD_PATH"; exit 1; }

        HOUR=$(NUMBER_PICKER "Час (0-23):" 12)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) HOUR=12 ;; esac
        MINUTE=$(NUMBER_PICKER "Минута (0-59):" 0)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MINUTE=0 ;; esac

        CRON_LINE="$MINUTE $HOUR * * * /bin/bash $PAYLOAD_PATH >> $LOOT_DIR/exec.log 2>&1 # NULLSEC_TASK"
        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -

        PROMPT "ПЕЙЛОУД ЗАПЛАНИРОВАН

$PAYLOAD_NAME будет запускаться
ежедневно в ${HOUR}:$(printf '%02d' $MINUTE)

Нажми OK для выхода."
        ;;

    5) # Просмотр журнала
        if [ -f "$LOOT_DIR/exec.log" ]; then
            LOG_LINES=$(wc -l < "$LOOT_DIR/exec.log")
            LOG_TAIL=$(tail -10 "$LOOT_DIR/exec.log")
            PROMPT "ЖУРНАЛ ВЫПОЛНЕНИЯ
Всего строк: $LOG_LINES

$LOG_TAIL

Нажми OK для выхода."
        else
            PROMPT "Журнал выполнения пока пуст.

Задачи ещё не выполнялись
или не было вывода.

Нажми OK для выхода."
        fi
        ;;
esac