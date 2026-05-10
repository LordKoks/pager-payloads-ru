#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Взломщик Чисел
# Author: NullSec
# Description: Игра в угадывание числа с темой хакерства
# Category: nullsec/games

LOOT_DIR="/mmc/nullsec/numbercracker"
mkdir -p "$LOOT_DIR"

PROMPT "ВЗЛОМЩИК ЧИСЕЛ

Взломайте зашифрованное
число до того, как
система заблокирует вас!

Каждая попытка дает
интел о цели.

Особенности:
- Множественная сложность
- Ограниченные попытки
- Система подсказок
- Трекинг рекордов

Нажмите ОК для начала."

PROMPT "СЛОЖНОСТЬ:

1. Скрипт Кидди (1-50)
2. Хакер (1-100)
3. Элита (1-500)
4. Л33Т (1-1000)

Выберите сложность далее."

DIFFICULTY=$(NUMBER_PICKER "Сложность (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DIFFICULTY=2 ;; esac

case $DIFFICULTY in
    1) MAX_NUM=50;   MAX_ATTEMPTS=8;  LABEL="Script Kiddie" ;;
    2) MAX_NUM=100;  MAX_ATTEMPTS=7;  LABEL="Hacker" ;;
    3) MAX_NUM=500;  MAX_ATTEMPTS=9;  LABEL="Elite" ;;
    4) MAX_NUM=1000; MAX_ATTEMPTS=10; LABEL="L33T" ;;
esac

SECRET=$((RANDOM % MAX_NUM + 1))
ATTEMPTS=0
CRACKED=0

resp=$(CONFIRMATION_DIALOG "БРИФИНГ МИССИИ

Сложность: $LABEL
Диапазон: 1 - $MAX_NUM
Попытки: $MAX_ATTEMPTS

Взломайте зашифрованное
число до блокировки системы!

Начать миссию?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

HINT_EVEN="unknown"
[ $((SECRET % 2)) -eq 0 ] && HINT_EVEN="ЧЕТНОЕ" || HINT_EVEN="НЕЧЕТНОЕ"

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ] && [ $CRACKED -eq 0 ]; do
    REMAINING=$((MAX_ATTEMPTS - ATTEMPTS))

    # Provide hints based on attempts used
    HINT_MSG=""
    if [ $ATTEMPTS -eq 2 ]; then
        HINT_MSG="ИНТЕЛ: Число $HINT_EVEN"
    elif [ $ATTEMPTS -eq 4 ]; then
        if [ $SECRET -le $((MAX_NUM / 3)) ]; then
            HINT_MSG="ИНТЕЛ: Нижняя треть"
        elif [ $SECRET -le $((MAX_NUM * 2 / 3)) ]; then
            HINT_MSG="ИНТЕЛ: Средняя треть"
        else
            HINT_MSG="ИНТЕЛ: Верхняя треть"
        fi
    elif [ $ATTEMPTS -ge 6 ]; then
        DIVISOR=5
        [ $((SECRET % DIVISOR)) -eq 0 ] && HINT_MSG="ИНТЕЛ: Делится на $DIVISOR" || HINT_MSG="ИНТЕЛ: НЕ дел на $DIVISOR"
    fi

    PROMPT "ПОПЫТКА ВЗЛОМА $((ATTEMPTS + 1))/$MAX_ATTEMPTS

Диапазон: 1 - $MAX_NUM
Осталось: $REMAINING
$HINT_MSG

[################----]
Дешифровка: $((ATTEMPTS * 100 / MAX_ATTEMPTS))%

Введите догадку далее."

    GUESS=$(NUMBER_PICKER "Догадка (1-$MAX_NUM):" $((MAX_NUM / 2)))
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) break ;; esac

    ATTEMPTS=$((ATTEMPTS + 1))

    if [ "$GUESS" -eq "$SECRET" ]; then
        CRACKED=1
    elif [ "$GUESS" -lt "$SECRET" ]; then
        DIFF=$((SECRET - GUESS))
        if [ $DIFF -le 5 ]; then
            PROXIMITY="BURNING HOT!"
        elif [ $DIFF -le 15 ]; then
            PROXIMITY="Very warm"
        elif [ $DIFF -le 50 ]; then
            PROXIMITY="Warm"
        else
            PROXIMITY="Cold"
        fi
        PROMPT "ДОСТУП ЗАПРЕЩЕН

$GUESS слишком МАЛО
Близость: $PROXIMITY

Нажмите ОК для повторной попытки."
    else
        DIFF=$((GUESS - SECRET))
        if [ $DIFF -le 5 ]; then
            PROXIMITY="BURNING HOT!"
        elif [ $DIFF -le 15 ]; then
            PROXIMITY="Very warm"
        elif [ $DIFF -le 50 ]; then
            PROXIMITY="Warm"
        else
            PROXIMITY="Cold"
        fi
        PROMPT "ДОСТУП ЗАПРЕЩЕН

$GUESS слишком ВЫСОКО
Близость: $PROXIMITY

Нажмите ОК для повторной попытки."
    fi
done

if [ $CRACKED -eq 1 ]; then
    SCORE=$(( (MAX_ATTEMPTS - ATTEMPTS + 1) * 100 + MAX_NUM ))

    PROMPT "*** ВЗЛОМАНО ***

ЧИСЛО: $SECRET
Попытки: $ATTEMPTS/$MAX_ATTEMPTS
Сложность: $LABEL
Очки: $SCORE

СИСТЕМА СКОМПРОМЕТИРОВАНА!

Нажмите ОК для выхода."
else
    SCORE=0

    PROMPT "*** БЛОКИРОВКА ***

СИСТЕМА ЗАБЛОКИРОВАНА!
Число было: $SECRET

Использовано попыток: $MAX_ATTEMPTS
Сложность: $LABEL
Очки: 0

Удачи в следующий раз.

Нажмите ОК для выхода."
fi

# Save score
echo "$(date +%Y%m%d_%H%M) | $LABEL | $ATTEMPTS/$MAX_ATTEMPTS | Score:$SCORE | $([ $CRACKED -eq 1 ] && echo WIN || echo LOSS)" >> "$LOOT_DIR/scores.txt"

# Show high scores
if [ -f "$LOOT_DIR/scores.txt" ]; then
    BEST=$(grep "WIN" "$LOOT_DIR/scores.txt" | sort -t'|' -k4 -rn | head -3)
    [ -n "$BEST" ] && PROMPT "РЕКОРДЫ

$BEST

Нажмите ОК для выхода."
fi
