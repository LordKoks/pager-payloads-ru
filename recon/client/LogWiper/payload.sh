#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Log Wiper
# Author: NullSec
# Description: Надежно очищает журналы операций с выборочными или полными вариантами
# Category: nullsec/stealth

LOOT_DIR="/mmc/nullsec/logwiper"
mkdir -p "$LOOT_DIR"

PROMPT "ОЧИСТКА ЛОГОВ

Надежно удаляет все
журналы операций и
следы расследования.

Режимы:
- Выборочная очистка
- Полное стирание
- Очистка лута NullSec
- Безопасная перезапись
- Очистка истории

Нажмите ОК для настройки."

# Analyze current logs
SPINNER_START "Анализ журналов..."

SYSLOG_SIZE=$(du -sh /var/log/ 2>/dev/null | awk '{print $1}')
LOOT_SIZE=$(du -sh /mmc/nullsec/ 2>/dev/null | awk '{print $1}')
TMP_SIZE=$(du -sh /tmp/ 2>/dev/null | awk '{print $1}')
HIST_EXISTS=0
[ -f ~/.ash_history ] || [ -f ~/.bash_history ] && HIST_EXISTS=1
DMESG_LINES=$(dmesg 2>/dev/null | wc -l)

SPINNER_STOP

PROMPT "АНАЛИЗ ЖУРНАЛОВ

Системные логи: $SYSLOG_SIZE
Лут NullSec: $LOOT_SIZE
Временные файлы: $TMP_SIZE
История оболочки: $([ $HIST_EXISTS -eq 1 ] && echo "Найдена" || echo "Отсутствует")
Сообщения ядра: $DMESG_LINES строк

Нажмите ОК для выбора режима."

PROMPT "РЕЖИМ СТИРКИ:

1. Только системные логи
2. Только лут NullSec
3. История оболочки
4. Временные файлы
5. Выборочно (выбрать)
6. ПОЛНОЕ СТИРАНИЕ (всё)

Выберите режим." 

WIPE_MODE=$(NUMBER_PICKER "Режим (1-6):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) WIPE_MODE=1 ;; esac

# Secure wipe method
PROMPT "МЕТОД СТИРКИ:

1. Быстрое удаление
2. Перезапись нулями
3. Случайная перезапись (3x)

Больше проходов = медленнее
но надежнее.

Выберите метод." 

WIPE_METHOD=$(NUMBER_PICKER "Метод (1-3):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) WIPE_METHOD=1 ;; esac

secure_wipe() {
    local filepath="$1"
    [ ! -f "$filepath" ] && return

    case $WIPE_METHOD in
        1) rm -f "$filepath" ;;
        2)
            local size=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
            dd if=/dev/zero of="$filepath" bs=1 count="$size" conv=notrunc 2>/dev/null
            rm -f "$filepath"
            ;;
        3)
            local size=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
            for pass in 1 2 3; do
                dd if=/dev/urandom of="$filepath" bs=1 count="$size" conv=notrunc 2>/dev/null
            done
            rm -f "$filepath"
            ;;
    esac
}

secure_wipe_dir() {
    local dirpath="$1"
    [ ! -d "$dirpath" ] && return
    find "$dirpath" -type f | while read -r f; do
        secure_wipe "$f"
    done
    rm -rf "$dirpath"
}

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ОЧИСТКУ ЛОГОВ?

Режим: $WIPE_MODE
Метод: $(case $WIPE_METHOD in 1) echo Быстрый;; 2) echo Нули;; 3) echo Случайный;; esac)

ВНИМАНИЕ: Это нельзя отменить! Все выбранные
журналы будут уничтожены.

Подтвердите?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Начинаю очистку логов..."
SPINNER_START "Стираю логи..."

WIPED_COUNT=0

case $WIPE_MODE in
    1) # System logs only
        for logfile in /var/log/messages /var/log/syslog /var/log/kern.log /var/log/auth.log \
                       /var/log/daemon.log /var/log/dmesg /var/log/wtmp /var/log/lastlog; do
            if [ -f "$logfile" ]; then
                secure_wipe "$logfile"
                WIPED_COUNT=$((WIPED_COUNT + 1))
            fi
        done
        # Очистить кольцо ядра
        dmesg -c >/dev/null 2>&1
        # Очистить оставшиеся логи
        find /var/log/ -name "*.log" -o -name "*.gz" -o -name "*.old" 2>/dev/null | while read -r f; do
            secure_wipe "$f"
            WIPED_COUNT=$((WIPED_COUNT + 1))
        done
        ;;

    2) # NullSec loot only
        for loot_dir in /mmc/nullsec/*/; do
            DIRNAME=$(basename "$loot_dir")
            [ "$DIRNAME" = "logwiper" ] && continue
            secure_wipe_dir "$loot_dir"
            WIPED_COUNT=$((WIPED_COUNT + 1))
        done
        ;;

    3) # Shell history
        for histfile in ~/.ash_history ~/.bash_history ~/.sh_history \
                        /root/.ash_history /root/.bash_history /tmp/.bash_history; do
            secure_wipe "$histfile"
            WIPED_COUNT=$((WIPED_COUNT + 1))
        done
        # Очистить текущую сессию
        history -c 2>/dev/null
        unset HISTFILE 2>/dev/null
        ;;

    4) # Temp files
        find /tmp/ -type f -name "*.log" -o -name "*.tmp" -o -name "*.pcap" \
            -o -name "*.csv" -o -name "*.cap" 2>/dev/null | while read -r f; do
            secure_wipe "$f"
            WIPED_COUNT=$((WIPED_COUNT + 1))
        done
        ;;

    5) # Selective
        PROMPT "ВЫБОР ЦЕЛЕЙ:

Стираем по очереди...

1=Да 2=Нет для каждого."

        for category in "Системные логи" "Лут NullSec" "История оболочки" "Временные файлы" "Сообщения ядра"; do
            resp=$(CONFIRMATION_DIALOG "Стереть: $category?")
            if [ "$resp" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
                case "$category" in
                    "Системные логи")
                        find /var/log/ -type f 2>/dev/null | while read -r f; do secure_wipe "$f"; done
                        WIPED_COUNT=$((WIPED_COUNT + 1))
                        ;;
                    "Лут NullSec")
                        for d in /mmc/nullsec/*/; do
                            [ "$(basename "$d")" = "logwiper" ] && continue
                            secure_wipe_dir "$d"
                        done
                        WIPED_COUNT=$((WIPED_COUNT + 1))
                        ;;
                    "История оболочки")
                        secure_wipe ~/.ash_history; secure_wipe ~/.bash_history
                        WIPED_COUNT=$((WIPED_COUNT + 1))
                        ;;
                    "Временные файлы")
                        find /tmp/ -type f \( -name "*.log" -o -name "*.tmp" -o -name "*.pcap" \) -delete 2>/dev/null
                        WIPED_COUNT=$((WIPED_COUNT + 1))
                        ;;
                    "Сообщения ядра")
                        dmesg -c >/dev/null 2>&1
                        WIPED_COUNT=$((WIPED_COUNT + 1))
                        ;;
                esac
            fi
        done
        ;;

    6) # TOTAL WIPE
        # System logs
        find /var/log/ -type f 2>/dev/null | while read -r f; do secure_wipe "$f"; WIPED_COUNT=$((WIPED_COUNT + 1)); done
        # NullSec loot (except logwiper)
        for d in /mmc/nullsec/*/; do
            [ "$(basename "$d")" = "logwiper" ] && continue
            secure_wipe_dir "$d"
        done
        # Shell history
        secure_wipe ~/.ash_history; secure_wipe ~/.bash_history; secure_wipe /root/.ash_history
        # Temp files
        find /tmp/ -type f \( -name "*.log" -o -name "*.tmp" -o -name "*.pcap" -o -name "*.csv" -o -name "*.cap" \) 2>/dev/null | while read -r f; do secure_wipe "$f"; done
        # Kernel messages
        dmesg -c >/dev/null 2>&1
        # Clear environment traces
        unset HISTFILE HISTSIZE HISTFILESIZE 2>/dev/null
        history -c 2>/dev/null
        WIPED_COUNT=999
        ;;
esac

SPINNER_STOP

PROMPT "ОЧИСТКА ЖУРНАЛОВ ЗАВЕРШЕНА

Удалено элементов: $WIPED_COUNT
Метод: $(case $WIPE_METHOD in 1) echo Быстрый;; 2) echo \"Нули\";; 3) echo \"Случайный 3x\";; esac)

Все следы уничтожены.

Нажмите ОК для выхода."
