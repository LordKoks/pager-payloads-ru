#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Карта Сети
# Author: bad-antics
# Description: Детальная разведка конкретной сети
# Category: nullsec/recon

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/recon"
mkdir -p "$LOOT_DIR"

PROMPT "КАРТА СЕТИ

Глубокая разведка
конкретной целевой сети.

Собирает:
- Все подключенные клиенты
- Типы устройств клиентов
- Силу сигнала
- Скорости данных
- Детали шифрования

Нажмите ОК для настройки."

PROMPT "ВЫБРАТЬ ЦЕЛЬ:

1. Сканировать и выбрать
2. Ввести BSSID вручную
3. Ввести SSID для поиска

Выберите опцию далее."

MODE=$(NUMBER_PICKER "Режим (1-3):" 1)

if [ "$MODE" -eq 1 ]; then
    SPINNER_START "Сканирую сети..."
    timeout 10 airodump-ng $IFACE --write-interval 1 -w /tmp/netscan --output-format csv 2>/dev/null
    SPINNER_STOP
    
    # Count networks
    NET_COUNT=$(grep -c "WPA\|WEP\|OPN" /tmp/netscan*.csv 2>/dev/null || echo 0)
    
    PROMPT "Найдено $NET_COUNT сетей

Выберите цель по номеру
на следующем экране.

Сети отсортированы по
силе сигнала."
    
    TARGET_NUM=$(NUMBER_PICKER "Сеть # (1-$NET_COUNT):" 1)
    
    # Get target info
    TARGET_LINE=$(grep "WPA\|WEP\|OPN" /tmp/netscan*.csv 2>/dev/null | sed -n "${TARGET_NUM}p")
    BSSID=$(echo "$TARGET_LINE" | cut -d',' -f1 | tr -d ' ')
    CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
    SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')
    
elif [ "$MODE" -eq 2 ]; then
    BSSID=$(MAC_PICKER "Целевой BSSID:")
    CHANNEL=$(NUMBER_PICKER "Канал:" 6)
    SSID="Unknown"
    
elif [ "$MODE" -eq 3 ]; then
    SSID=$(TEXT_PICKER "Целевой SSID:" "")
    SPINNER_START "Ищу сеть..."
    timeout 10 airodump-ng $IFACE --essid "$SSID" --write-interval 1 -w /tmp/ssidscan --output-format csv 2>/dev/null
    SPINNER_STOP
    BSSID=$(grep "$SSID" /tmp/ssidscan*.csv 2>/dev/null | head -1 | cut -d',' -f1 | tr -d ' ')
    CHANNEL=$(grep "$SSID" /tmp/ssidscan*.csv 2>/dev/null | head -1 | cut -d',' -f4 | tr -d ' ')
fi

DURATION=$(NUMBER_PICKER "Длительность сканирования (сек):" 60)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac

REPORT="$LOOT_DIR/netmap_${BSSID//:/}_$(date +%Y%m%d_%H%M).txt"

resp=$(CONFIRMATION_DIALOG "КАРТИРОВАТЬ СЕТЬ?

SSID: $SSID
BSSID: $BSSID
Канал: $CHANNEL
Длительность: ${DURATION}с

Нажмите ОК для начала.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Картирую $SSID..."

# Lock to target channel
iwconfig $IFACE channel $CHANNEL

# Deep scan
airodump-ng $IFACE --bssid "$BSSID" -c $CHANNEL --write-interval 1 -w /tmp/deepmap --output-format csv &
SCAN_PID=$!

sleep $DURATION
kill $SCAN_PID 2>/dev/null

# Generate report
echo "======================================" > "$REPORT"
echo "       КАРТА СЕТИ NULLSEC             " >> "$REPORT"
echo "======================================" >> "$REPORT"
echo "" >> "$REPORT"
echo "Цель: $SSID" >> "$REPORT"
echo "BSSID: $BSSID" >> "$REPORT"
echo "Канал: $CHANNEL" >> "$REPORT"
echo "Сканировано: $(date)" >> "$REPORT"
echo "" >> "$REPORT"
echo "--- ПОДКЛЮЧЕННЫЕ КЛИЕНТЫ ---" >> "$REPORT"

# Parse clients
CLIENT_COUNT=0
while IFS=',' read -r mac firstseen lastseen power packets bssid probed; do
    mac=$(echo "$mac" | tr -d ' ')
    if [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [ "$bssid" = "$BSSID" ]; then
        CLIENT_COUNT=$((CLIENT_COUNT + 1))
        echo "" >> "$REPORT"
        echo "Клиент #$CLIENT_COUNT" >> "$REPORT"
        echo "  MAC: $mac" >> "$REPORT"
        echo "  Сигнал: $power dBm" >> "$REPORT"
        echo "  Пакеты: $packets" >> "$REPORT"
        echo "  Последний раз: $lastseen" >> "$REPORT"
    fi
done < /tmp/deepmap*.csv 2>/dev/null

echo "" >> "$REPORT"
echo "======================================" >> "$REPORT"
echo "Всего клиентов: $CLIENT_COUNT" >> "$REPORT"
echo "======================================" >> "$REPORT"

PROMPT "КАРТИРОВАНИЕ ЗАВЕРШЕНО

SSID: $SSID
Найдено клиентов: $CLIENT_COUNT

Отчет сохранен в:
$REPORT

Нажмите ОК для выхода."
