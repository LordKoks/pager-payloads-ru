#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Ссылка Pager
# Author: NullSec
# Description: Создает SSH туннель для удаленного доступа к UI Pager
# Category: nullsec/remote

LOOT_DIR="/mmc/nullsec/pagerlink"
mkdir -p "$LOOT_DIR"

PROMPT "ССЫЛКА PAGER

Создает SSH туннель, чтобы
вы могли получить доступ к
UI Pager удаленно отовсюду.

Особенности:
- Удаленный доступ к Pager
- Безопасный SSH туннель
- Автопереподключение
- Мониторинг статуса
- Логирование соединений

Нажмите ОК для настройки."

# Check for SSH
if ! command -v ssh >/dev/null 2>&1; then
    ERROR_DIALOG "SSH клиент не найден!

opkg update && opkg install
openssh-client"
    exit 1
fi

# Check connectivity
if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    ERROR_DIALOG "Нет интернет-соединения!

PagerLink требует
активного WAN uplink."
    exit 1
fi

# Detect Pager UI port
PAGER_PORT=1471
if ! netstat -tln 2>/dev/null | grep -q ":${PAGER_PORT} "; then
    PROMPT "ОБНАРУЖЕНИЕ ПОРТА PAGER

Порт по умолчанию 1471 может
не прослушиваться. UI Pager
может использовать другой порт.

Введите порт UI Pager."
    PAGER_PORT=$(NUMBER_PICKER "Порт Pager:" 1471)
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PAGER_PORT=1471 ;; esac
fi

LOG "Pager UI port: $PAGER_PORT"

REMOTE_HOST=$(TEXT_PICKER "Удаленный сервер:" "relay.example.com")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) REMOTE_HOST="" ;; esac
[ -z "$REMOTE_HOST" ] && { ERROR_DIALOG "Требуется удаленный сервер!"; exit 1; }

REMOTE_USER=$(TEXT_PICKER "Удаленный пользователь:" "pager")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) REMOTE_USER="pager" ;; esac

REMOTE_SSH_PORT=$(NUMBER_PICKER "Удаленный порт SSH:" 22)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) REMOTE_SSH_PORT=22 ;; esac

EXPOSE_PORT=$(NUMBER_PICKER "Удаленный порт экспозиции:" 8471)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) EXPOSE_PORT=8471 ;; esac
[ "$EXPOSE_PORT" -lt 1024 ] && EXPOSE_PORT=8471
[ "$EXPOSE_PORT" -gt 65535 ] && EXPOSE_PORT=8471

# SSH key setup
KEY_FILE="$LOOT_DIR/pagerlink_key"
if [ ! -f "$KEY_FILE" ]; then
    resp=$(CONFIRMATION_DIALOG "Ключ SSH не найден.

Сгенерировать новую пару
ключей?
Вам нужно будет добавить
публичный ключ на удаленный
сервер после этого.

Нажмите ОК для генерации.")
    if [ "$resp" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
        SPINNER_START "Генерация ключа SSH..."
        ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "pagerlink@pineapple" >/dev/null 2>&1
        SPINNER_STOP
        PUB_KEY=$(cat "${KEY_FILE}.pub")
        PROMPT "ПУБЛИЧНЫЙ КЛЮЧ

Добавьте на удаленный сервер
authorized_keys для пользователя
${REMOTE_USER}:

$PUB_KEY

Нажмите ОК когда готово."
    else
        ERROR_DIALOG "Требуется ключ SSH!

Поместите ключ в:
$KEY_FILE"; exit 1
    fi
fi
chmod 600 "$KEY_FILE"

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ССЫЛКУ PAGER?

Локально: localhost:$PAGER_PORT
Удаленно: $REMOTE_HOST:$EXPOSE_PORT
Пользователь: $REMOTE_USER

Доступ к Pager удаленно:
http://$REMOTE_HOST:$EXPOSE_PORT

Нажмите ОК для подключения.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LINK_LOG="$LOOT_DIR/link_$TIMESTAMP.log"
PID_FILE="$LOOT_DIR/pagerlink.pid"

# Kill existing link
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    kill "$OLD_PID" 2>/dev/null
    rm -f "$PID_FILE"
fi

LOG "PagerLink starting to $REMOTE_HOST"
SPINNER_START "Установка связи..."

# Launch tunnel with auto-reconnect
(
    RECONNECT_DELAY=10
    while true; do
        echo "[$(date)] Connecting tunnel..." >> "$LINK_LOG"
        ssh -N \
            -o StrictHostKeyChecking=no \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -o ConnectTimeout=15 \
            -i "$KEY_FILE" \
            -p "$REMOTE_SSH_PORT" \
            -R "${EXPOSE_PORT}:localhost:${PAGER_PORT}" \
            "${REMOTE_USER}@${REMOTE_HOST}" >> "$LINK_LOG" 2>&1

        EXIT_CODE=$?
        echo "[$(date)] Disconnected (exit $EXIT_CODE), retry in ${RECONNECT_DELAY}s" >> "$LINK_LOG"

        # Back off on repeated failures
        sleep "$RECONNECT_DELAY"
        [ "$RECONNECT_DELAY" -lt 120 ] && RECONNECT_DELAY=$((RECONNECT_DELAY + 10))
    done
) &
LINK_PID=$!
echo "$LINK_PID" > "$PID_FILE"

sleep 5
SPINNER_STOP

# Check status
if kill -0 "$LINK_PID" 2>/dev/null; then
    LOG "PagerLink active (PID: $LINK_PID)"

    PROMPT "ССЫЛКА PAGER АКТИВНА

Статус: ПОДКЛЮЧЕНО
PID: $LINK_PID
Автопереподключение: ВКЛ

Доступ к UI Pager удаленно:
http://$REMOTE_HOST:$EXPOSE_PORT

Лог: $LINK_LOG

Работает в фоне.
Для остановки: kill $LINK_PID"
else
    ERROR_DIALOG "СВЯЗЬ НЕ УДАЛАСЬ

Не удалось установить туннель.
Проверьте учетные данные сервера
и сетевую связность.

Лог: $LINK_LOG"
    rm -f "$PID_FILE"
fi
