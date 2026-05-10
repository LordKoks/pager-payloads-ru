#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Обновлятор Payload NullSec
# Author: bad-antics
# Description: Скачивает последние payload NullSec из репозитория GitHub
# Category: nullsec

PROMPT "ОБНОВЛЯТОР PAYLOAD
━━━━━━━━━━━━━━━━━━━━━━━━━
Обновить payload NullSec
из GitHub.

Требует подключения
к интернету.

Нажмите ОК для проверки."

# Check connectivity
SPINNER_START "Проверка подключения..."
if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
    SPINNER_STOP
    ERROR_DIALOG "Нет интернета!\nПодключитесь в режиме клиента."
    exit 1
fi
SPINNER_STOP

REPO="https://raw.githubusercontent.com/bad-antics/nullsec-pineapple-suite/main"
PAYLOAD_DIR="/root/payloads/user/nullsec"
BACKUP_DIR="/mmc/nullsec/backup/payloads_$(date +%Y%m%d_%H%M%S)"

resp=$(CONFIRMATION_DIALOG "Обновить payload NullSec?

Текущие payload будут
сначала сохранены в резерв.

Продолжить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

# Backup current
SPINNER_START "Создание резервной копии..."
mkdir -p "$BACKUP_DIR"
cp -r "$PAYLOAD_DIR"/* "$BACKUP_DIR/" 2>/dev/null
SPINNER_STOP

# Download manifest
SPINNER_START "Скачивание обновлений..."
wget -q -O /tmp/payload_manifest.txt "$REPO/manifest.txt" 2>/dev/null

UPDATED=0
FAILED=0
if [ -f /tmp/payload_manifest.txt ]; then
    while read -r payload_path; do
        [ -z "$payload_path" ] && continue
        DIR=$(dirname "$payload_path")
        mkdir -p "$PAYLOAD_DIR/$DIR" 2>/dev/null
        if wget -q -O "$PAYLOAD_DIR/$payload_path" "$REPO/payloads/$payload_path" 2>/dev/null; then
            chmod +x "$PAYLOAD_DIR/$payload_path" 2>/dev/null
            UPDATED=$((UPDATED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    done < /tmp/payload_manifest.txt
fi
SPINNER_STOP

PROMPT "ОБНОВЛЕНИЕ ЗАВЕРШЕНО
━━━━━━━━━━━━━━━━━━━━━━━━━
Обновлено: $UPDATED payload
Не удалось: $FAILED
Резерв: $(basename $BACKUP_DIR)

Обновите список payload
для просмотра новых."
