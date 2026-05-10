#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Название: Дедупликация хэндшейков
# Author: Unit981
# Описание: Обновлённый алерт на захват хэндшейка, проверяет дубликаты по MAC точки доступа и сейчас настроен удалять дубликатные хэндшейки и связанные PCAP-файлы, чтобы порядок был чище.
# Version: 1.0

# Установка директории и переменных
HANDSHAKE_DIR="/root/loot/handshakes/"
PCAP="$_ALERT_HANDSHAKE_PCAP_PATH"

# Извлечение SSID из beacon-кадров
SSID=$(tcpdump -r "$PCAP" -e -I -s 256 \
  | sed -n 's/.*Beacon (\([^)]*\)).*/\1/p' \
  | head -n 1)

# Резервный вариант, если SSID не найден
[ -n "$SSID" ] || SSID="НЕИЗВЕСТНЫЙ_SSID"

# Убедиться, что MAC можно искать
mac_clean=$(printf "%s" "$_ALERT_HANDSHAKE_AP_MAC_ADDRESS" | sed 's/[[:space:]]//g')
mac_upper=${mac_clean^^}

# Подсчитать файлы, содержащие MAC в имени
handshake_count=$(find "$HANDSHAKE_DIR" -type f -name "*${mac_upper}*.22000" 2>/dev/null | wc -l)
pcap_count=$(find "$HANDSHAKE_DIR" -type f -name "*${mac_upper}*.pcap" 2>/dev/null | wc -l)

# Проверка, существует ли уже полный хэндшейк для этого MAC AP
existing_file=$(find "$HANDSHAKE_DIR" -type f -name "*${mac_upper}*handshake.22000" 2>/dev/null | head -n 1)

# Проверка дубликатов по количеству
if [ "$handshake_count" -gt 1 ]; then
    ALERT "#@ ВЗЛОМАЙТЕ ПЛАНЕТУ @# \n\n Хэндшейк захвачен! \n Обнаружен дубликат хэндшейка для \n SSID: $SSID - MAC: $_ALERT_HANDSHAKE_AP_MAC_ADDRESS \n Всего хэндшейков: $handshake_count"
    # Закомментируйте строки 34-36, чтобы дубликаты не удалялись автоматически
    ALERT "#@ Дедупликация АКТИВНА @# \n\n Удаляю дубликат хэндшейка и PCAP для: \n SSID: $SSID \n MAC адрес AP: $_ALERT_HANDSHAKE_AP_MAC_ADDRESS"
    rm -rf "$_ALERT_HANDSHAKE_HASHCAT_PATH"
    rm -rf "$_ALERT_HANDSHAKE_PCAP_PATH"
else
    ALERT "#@ ВЗЛОМАЙТЕ ПЛАНЕТУ @# \n\n Захвачен новый хэндшейк: SSID: $SSID \n BSSID точки доступа: $_ALERT_HANDSHAKE_AP_MAC_ADDRESS \n MAC клиента: $_ALERT_HANDSHAKE_CLIENT_MAC_ADDRESS"
fi