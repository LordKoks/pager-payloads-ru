. /root/payloads/library/nullsec-ui.sh
. /root/payloads/library/nullsec-ui.sh
#!/bin/bash
# Title: Быстрое сканирование
# Author: bad-antics
# Description: Быстрое 30-секундное сканирование окружения WiFi
# Category: nullsec/recon

# Автоматически определяет правильный беспроводной интерфейс (экспортирует $IFACE).
# При отсутствии интерфейса показывает диалог ошибки.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "БЫСТРОЕ СКАНИРОВАНИЕ

Быстрое 30-секундное сканирование
всех соседних сетей WiFi.

Показывает:
- Названия сетей
- Типы безопасности
- Мощность сигнала
- Количество клиентов

Нажмите ОК для сканирования."

SPINNER_START "Сканирование 30 секунд..."
timeout 30 airodump-ng $IFACE --write-interval 5 -w /tmp/quickscan --output-format csv 2>/dev/null
SPINNER_STOP

# Count results
AP_COUNT=$(grep -c "WPA\|WEP\|OPN" /tmp/quickscan*.csv 2>/dev/null || echo 0)
CLIENT_COUNT=$(grep -E "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}," /tmp/quickscan*.csv 2>/dev/null | grep -v BSSID | wc -l || echo 0)

# Count by security
WPA3=$(grep -c "WPA3" /tmp/quickscan*.csv 2>/dev/null || echo 0)
WPA2=$(grep -c "WPA2" /tmp/quickscan*.csv 2>/dev/null || echo 0)
WPA=$(grep "WPA[^23]" /tmp/quickscan*.csv 2>/dev/null | grep -v WPA2 | grep -v WPA3 | wc -l || echo 0)
WEP=$(grep -c "WEP" /tmp/quickscan*.csv 2>/dev/null || echo 0)
OPEN=$(grep -c " OPN" /tmp/quickscan*.csv 2>/dev/null || echo 0)

PROMPT "СКАНИРОВАНИЕ ЗАВЕРШЕНО

Сетей: $AP_COUNT
Клиентов: $CLIENT_COUNT

Разбор по безопасности:
WPA3: $WPA3
WPA2: $WPA2
WPA: $WPA
WEP: $WEP
Открытые: $OPEN

Нажмите ОК для топ 5."

# Show top 5 strongest
PROMPT "ТОП 5 СЕТЕЙ

$(grep "WPA\|WEP\|OPN" /tmp/quickscan*.csv 2>/dev/null | sort -t',' -k9 -nr | head -5 | while IFS=',' read -r bssid first last channel speed privacy cipher auth power beacons iv lan_ip id_len essid key; do
    essid=$(echo "$essid" | tr -d ' ')
    power=$(echo "$power" | tr -d ' ')
    privacy=$(echo "$privacy" | tr -d ' ')
    echo "$essid ($power dBm) $privacy"
done)

Нажмите ОК для выхода."
