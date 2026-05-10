#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Pager Pong
# Author: NullSec
# Description: Простая текстовая игра Pong на дисплее Pager
# Category: nullsec/games

LOOT_DIR="/mmc/nullsec/pagerpong"
mkdir -p "$LOOT_DIR"

PROMPT "PAGER PONG

Классическая игра Pong
на вашем дисплее Pager!

Используйте выбор числа для
перемещения ракетки.

Особенности:
- Один игрок против CPU
- Отслеживание счета
- Регулируемая сложность
- Доска рекордов

Нажмите ОК для старта."

# Difficulty selection
PROMPT "СЛОЖНОСТЬ:

1. Легко (медленный мяч)
2. Средне
3. Трудно (быстрый мяч)
4. Безумно

Выберите сложность далее."

DIFFICULTY=$(NUMBER_PICKER "Сложность (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DIFFICULTY=2 ;; esac

case $DIFFICULTY in
    1) CPU_MISS_CHANCE=40; BALL_LABEL="Медленный" ;;
    2) CPU_MISS_CHANCE=25; BALL_LABEL="Средний" ;;
    3) CPU_MISS_CHANCE=15; BALL_LABEL="Быстрый" ;;
    4) CPU_MISS_CHANCE=5;  BALL_LABEL="Безумный" ;;
esac

# Game state
FIELD_W=20
FIELD_H=9
PLAYER_POS=4
CPU_POS=4
BALL_X=10
BALL_Y=4
BALL_DX=1
BALL_DY=1
PLAYER_SCORE=0
CPU_SCORE=0
MAX_SCORE=5

render_field() {
    local output=""
    for y in $(seq 0 $((FIELD_H - 1))); do
        local line=""
        for x in $(seq 0 $((FIELD_W - 1))); do
            if [ $x -eq 0 ]; then
                # Player paddle (left)
                if [ $y -ge $((PLAYER_POS - 1)) ] && [ $y -le $((PLAYER_POS + 1)) ]; then
                    line="${line}|"
                else
                    line="${line} "
                fi
            elif [ $x -eq $((FIELD_W - 1)) ]; then
                # CPU paddle (right)
                if [ $y -ge $((CPU_POS - 1)) ] && [ $y -le $((CPU_POS + 1)) ]; then
                    line="${line}|"
                else
                    line="${line} "
                fi
            elif [ $x -eq $BALL_X ] && [ $y -eq $BALL_Y ]; then
                line="${line}O"
            elif [ $x -eq $((FIELD_W / 2)) ]; then
                line="${line}:"
            else
                line="${line} "
            fi
        done
        output="${output}${line}\n"
    done
    echo -e "$output"
}

# Game loop
while [ $PLAYER_SCORE -lt $MAX_SCORE ] && [ $CPU_SCORE -lt $MAX_SCORE ]; do

    FIELD=$(render_field)

    # Move player via number picker
    PLAYER_POS=$(NUMBER_PICKER "Позиция ракетки (1-7):" $PLAYER_POS)
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) break ;; esac
    [ $PLAYER_POS -lt 1 ] && PLAYER_POS=1
    [ $PLAYER_POS -gt 7 ] && PLAYER_POS=7

    # Move ball
    BALL_X=$((BALL_X + BALL_DX))
    BALL_Y=$((BALL_Y + BALL_DY))

    # Wall bounce (top/bottom)
    if [ $BALL_Y -le 0 ]; then
        BALL_Y=1
        BALL_DY=1
    elif [ $BALL_Y -ge $((FIELD_H - 1)) ]; then
        BALL_Y=$((FIELD_H - 2))
        BALL_DY=-1
    fi

    # Player paddle check (left wall)
    if [ $BALL_X -le 1 ]; then
        if [ $BALL_Y -ge $((PLAYER_POS - 1)) ] && [ $BALL_Y -le $((PLAYER_POS + 1)) ]; then
            BALL_DX=1
            BALL_X=2
            # Angle based on paddle hit position
            HIT_POS=$((BALL_Y - PLAYER_POS))
            BALL_DY=$HIT_POS
            [ $BALL_DY -eq 0 ] && BALL_DY=$((RANDOM % 2 * 2 - 1))
        else
            CPU_SCORE=$((CPU_SCORE + 1))
            BALL_X=10; BALL_Y=4; BALL_DX=1
            PROMPT "CPU ЗАБИВАЕТ!

Вы: $PLAYER_SCORE
CPU: $CPU_SCORE

Нажмите ОК для продолжения."
        fi
    fi

    # CPU paddle check (right wall)
    if [ $BALL_X -ge $((FIELD_W - 2)) ]; then
        if [ $BALL_Y -ge $((CPU_POS - 1)) ] && [ $BALL_Y -le $((CPU_POS + 1)) ]; then
            BALL_DX=-1
            BALL_X=$((FIELD_W - 3))
        else
            PLAYER_SCORE=$((PLAYER_SCORE + 1))
            BALL_X=10; BALL_Y=4; BALL_DX=-1
            PROMPT "ВЫ ЗАБИВАЕТЕ!

Вы: $PLAYER_SCORE
CPU: $CPU_SCORE

Нажмите ОК для продолжения."
        fi
    fi

    # CPU AI movement
    if [ $((RANDOM % 100)) -ge $CPU_MISS_CHANCE ]; then
        if [ $BALL_Y -gt $CPU_POS ]; then
            CPU_POS=$((CPU_POS + 1))
        elif [ $BALL_Y -lt $CPU_POS ]; then
            CPU_POS=$((CPU_POS - 1))
        fi
    fi
    [ $CPU_POS -lt 1 ] && CPU_POS=1
    [ $CPU_POS -gt 7 ] && CPU_POS=7

    FIELD=$(render_field)

    PROMPT "PAGER PONG
Вы:$PLAYER_SCORE  CPU:$CPU_SCORE

$FIELD
Переместите ракетку далее."

done

# Game over
if [ $PLAYER_SCORE -ge $MAX_SCORE ]; then
    RESULT="ВЫ ПОБЕДИЛИ!"
else
    RESULT="CPU ПОБЕЖДАЕТ!"
fi

# Save high score
HISCORE_FILE="$LOOT_DIR/highscores.txt"
echo "$(date +%Y%m%d_%H%M) | $PLAYER_SCORE-$CPU_SCORE | $BALL_LABEL | $RESULT" >> "$HISCORE_FILE"

BEST=$(sort -t'|' -k2 -rn "$HISCORE_FILE" 2>/dev/null | head -3)

PROMPT "ИГРА ОКОНЧЕНА!

$RESULT

Финал: Вы $PLAYER_SCORE - $CPU_SCORE CPU
Сложность: $BALL_LABEL

Рекорды:
$BEST

Нажмите ОК для выхода."
