#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: NullSec \u0420\u0430\u0441\u0448\u0438\u0440\u0438\u0442\u0435\u043b\u044c \u0440\u0430\u0434\u0438\u0443\u0441\u0430\n# Author: bad-antics\n# Description: \u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u0441\u044f \u043a \u0441\u0435\u0442\u0438 \u0438 \u0442\u0440\u0430\u043d\u0441\u043b\u044f\u0446\u0438\u043e\u043d\u0438\u0440\u0443\u0435\u0442 hotspot \u0441 \u0447\u0430\u0444\u043e\u0432\u044b\u043c SSID\n# Category: nullsec/utility\n\n# \u0410\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438 \u043e\u043f\u0440\u0435\u0434\u0435\u043b\u044f\u0435\u0442 \u043f\u0440\u0430\u0432\u0438\u043b\u044c\u043d\u044b\u0439 \u0431\u0435\u0441\u043f\u0440\u043e\u0432\u043e\u0434\u043d\u043e\u0439 \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441 (\u044d\u043a\u0441\u043f\u043e\u0440\u0442\u0438\u0440\u0443\u0435\u0442 $IFACE).\n# \u041f\u0440\u0438 \u043e\u0442\u0441\u0443\u0442\u0441\u0442\u0432\u0438\u0438 \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441\u0430 \u043f\u043e\u043a\u0430\u0437\u044b\u0432\u0430\u0435\u0442 \u0434\u0438\u0430\u043b\u043e\u0433 \u043e\u0448\u0438\u0431\u043a\u0438.\n. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . \"$(dirname \"$0\")/../../../lib/nullsec-iface.sh\"\nnullsec_require_iface || exit 1\n\nPROMPT \"\u041d\u041e\u041b\u041b\u0421\u0415\u0426 \u0420\u0410\u0421\u0428\u0418\u0420\u0418\u0422\u0415\u041b\u042c \u0420\u0410\u0414\u0418\u0423\u0421\u0410\n\n\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u0435\u0441\u044c \u043a \u0432\u0430\u0448\u0435\u0439 \u0441\u0435\u0442\u0438\n\u0438 \u0442\u0440\u0430\u043d\u0441\u043b\u044f\u0446\u0438\u043e\u043d\u0438\u0440\u0443\u0439\u0442\u0435 hotspot\n\u0441 \u043f\u043e\u0434\u0434\u0435\u043b\u0430\u043d\u043d\u044b\u043c SSID.\n\n\u0420\u0430\u0431\u043e\u0442\u0430\u0435\u0442 \u0441:\n- \u0414\u043e\u043c\u0430\u0448\u043d\u0438\u043c WiFi\n- \u041c\u043e\u0431\u0438\u043b\u044c\u043d\u044b\u043c hotspot\n- \u041b\u044e\u0431\u044b\u043c WPA \u0440\u0435\u0436\u0438\u043c\u043e\u043c\n\n\u041e\u043f\u0435\u0440\u0430\u0442\u043e\u0440 \u0432\u0432\u043e\u0434\u0438\u0442 \u0432 \u0441\u0438\u0433\u043d\u0430\u043b!\n\n\u041d\u0430\u0436\u043c\u0438\u0442\u0435 \u041e\u041a \u0434\u043b\u044f \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438.\"\n\nPROMPT \"\u0412\u042b\u0411\u041e\u0420 \u0418\u0421\u0422\u041e\u0427\u041d\u0418\u041a\u0410:\n\n1. \u041d\u0430\u0439\u0442\u0438 \u0441\u0435\u0442\u044c\n2. \u0412\u0432\u0435\u0441\u0442\u0438 SSID \u0440\u0443\u0447\u043d\u043e\n3. \u041c\u043e\u0431\u0438\u043b\u044c\u043d\u044b\u0439 hotspot\n\n\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0432\u0430\u0440\u0438\u0430\u043d\u0442.\"\n\nSOURCE_MODE=$(NUMBER_PICKER \"\u0418\u0441\u0442\u043e\u0447\u043d\u0438\u043a (1-3):\" 1)"

case $SOURCE_MODE in
    1) # Сканирование
        SPINNER_START "Сканирование сетей..."
        timeout 12 airodump-ng $IFACE --encrypt wpa --write-interval 1 -w /tmp/extscan --output-format csv 2>/dev/null
        SPINNER_STOP
        
        NET_COUNT=$(grep -c "WPA" /tmp/extscan*.csv 2>/dev/null || echo 0)
        PROMPT "Найдено $NET_COUNT сетей"
        
        TARGET_NUM=$(NUMBER_PICKER "Номер сети:" 1)
        TARGET_LINE=$(grep "WPA" /tmp/extscan*.csv 2>/dev/null | sed -n "${TARGET_NUM}p")
        SOURCE_SSID=$(echo "$TARGET_LINE" | cut -d',' -f14 | tr -d ' ')
        SOURCE_CHANNEL=$(echo "$TARGET_LINE" | cut -d',' -f4 | tr -d ' ')
        ;;
    2) # Мануально
        SOURCE_SSID=$(TEXT_PICKER "Источник SSID:" "MyСеть")
        SOURCE_CHANNEL=$(NUMBER_PICKER "Канал:" 6)
        ;;
    3) # Мобильный hotspot
        PROMPT "РЕЖИМ МОБИЛЬНОГО HOTSPOT

Обычные названия:
- iPhone (Ваше имя)
- AndroidAP
- Galaxy S## (XXXX)

Введите название."
        SOURCE_SSID=$(TEXT_PICKER "Hotspot SSID:" "iPhone")
        SOURCE_CHANNEL=$(NUMBER_PICKER "Канал (1,6,11):" 6)
        ;;
esac

SOURCE_PASS=$(TEXT_PICKER "Пароль источника:" "")
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) 
    ERROR_DIALOG "Пароль требуется!"
    exit 1
    ;;
esac

PROMPT "ОПЦИИ SSID НЮРТ:

1. Оно искусство
2. Клонировать соседнюю
3. Пресеты

Выберите вариант."

SSID_MODE=$(NUMBER_PICKER "Режим SSID (1-3):" 1)

case $SSID_MODE in
    1) # Оно искусство
        HOTSPOT_SSID=$(TEXT_PICKER "Hotspot SSID:" "Free_WiFi")
        ;;
    2) # Клонирование
        SPINNER_START "Поиск SSID..."
        timeout 8 airodump-ng $IFACE --write-interval 1 -w /tmp/clonescan --output-format csv 2>/dev/null
        SPINNER_STOP
        
        CLONE_COUNT=$(grep -c "WPA\|OPN" /tmp/clonescan*.csv 2>/dev/null || echo 0)
        PROMPT "Найдено $CLONE_COUNT сетей для клонирования"
        
        CLONE_NUM=$(NUMBER_PICKER "Клонирую сеть #:" 1)
        CLONE_LINE=$(grep "WPA\|OPN" /tmp/clonescan*.csv 2>/dev/null | sed -n "${CLONE_NUM}p")
        HOTSPOT_SSID=$(echo "$CLONE_LINE" | cut -d',' -f14 | tr -d ' ')
        ;;
    3) # Пресеты
        PROMPT "ПРЕСЕТНЫЕ СЕТИ:

1. xfinitywifi
2. attwifi
3. Starbucks WiFi
4. McDonald's Free WiFi
5. Airport_Free_WiFi
6. Hotel_Guest

Выберите вариант."
        PRESET=$(NUMBER_PICKER "Пресет (1-6):" 1)
        case $PRESET in
            1) HOTSPOT_SSID="xfinitywifi" ;;
            2) HOTSPOT_SSID="attwifi" ;;
            3) HOTSPOT_SSID="Starbucks WiFi" ;;
            4) HOTSPOT_SSID="McDonald's Free WiFi" ;;
            5) HOTSPOT_SSID="Airport_Free_WiFi" ;;
            6) HOTSPOT_SSID="Hotel_Guest" ;;
        esac
        ;;
esac

PROMPT "БЕЗОПАСНОСТЬ HOTSPOT:

1. Открыта (без пароля)
2. WPA2 с паролем

Выберите вариант."

SEC_MODE=$(NUMBER_PICKER "Безопасность (1-2):" 1)

if [ "$SEC_MODE" -eq 2 ]; then
    HOTSPOT_PASS=$(TEXT_PICKER "Пароль Hotspot:" "nullsec123")
fi

# Нравно канал для hotspot
if [ "$SOURCE_CHANNEL" -le 6 ]; then
    HOTSPOT_CHANNEL=11
else
    HOTSPOT_CHANNEL=1
fi

resp=$(CONFIRMATION_DIALOG "ПУСТИТЬ ОТРАВ?

Настоящий: $SOURCE_SSID
Hotspot: $HOTSPOT_SSID
Безопасность: $([ \"$SEC_MODE\" -eq 2 ] && echo WPA2 || echo Открыта)

Нажмите ОК для запуска.")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

killall wpa_supplicant hostapd dnsmasq 2>/dev/null

LOG "Подключаюсь к $SOURCE_SSID..."

# Create wpa_supplicant config
cat > /tmp/wpa_source.conf << EOF
network={
    ssid="$SOURCE_SSID"
    psk="$SOURCE_PASS"
    key_mgmt=WPA-PSK
}
EOF

# Need two interfaces - check if wlan1 exists or use virtual
if [ -d "/sys/class/net/wlan1" ]; then
    CLIENT_IF="wlan1"
    AP_IF="$IFACE"
else
    # Create virtual interface
    iw dev $IFACE interface add wlan0_ap type __ap 2>/dev/null || {
        ERROR_DIALOG "Невозможно создать интерфейс AP. Требуется 2 адаптера WiFi или поддержка режима AP."
        exit 1
    }
    CLIENT_IF="$IFACE"
    AP_IF="wlan0_ap"
fi

# Подключится к сети источника
wpa_supplicant -B -i $CLIENT_IF -c /tmp/wpa_source.conf
sleep 5
dhclient $CLIENT_IF 2>/dev/null || udhcpc -i $CLIENT_IF 2>/dev/null

# Проверка соединения
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    ERROR_DIALOG "Не удалось подключиться к $SOURCE_SSID

Проверьте пароль."
    killall wpa_supplicant 2>/dev/null
    exit 1
fi

LOG "Подключено! Запускаю hotspot..."

# Настройка hotspot
if [ "$SEC_MODE" -eq 2 ]; then
cat > /tmp/hotspot.conf << EOF
interface=$AP_IF
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=$HOTSPOT_CHANNEL
auth_algs=1
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
else
cat > /tmp/hotspot.conf << EOF
interface=$AP_IF
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=$HOTSPOT_CHANNEL
auth_algs=1
wpa=0
EOF
fi

# Запуск hostapd
hostapd /tmp/hotspot.conf &
sleep 2

# Настройка AP интерфейса
ifconfig $AP_IF 192.168.50.1 netmask 255.255.255.0 up

# DHCP для клиентов hotspot
cat > /tmp/hotspot_dhcp.conf << EOF
interface=$AP_IF
dhcp-range=192.168.50.10,192.168.50.200,12h
dhcp-option=3,192.168.50.1
dhcp-option=6,8.8.8.8,8.8.4.4
EOF
dnsmasq -C /tmp/hotspot_dhcp.conf &

# Включите NAT/маршрутизацию
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o $CLIENT_IF -j MASQUERADE
iptables -A FORWARD -i $AP_IF -o $CLIENT_IF -j ACCEPT
iptables -A FORWARD -i $CLIENT_IF -o $AP_IF -m state --state RELATED,ESTABLISHED -j ACCEPT

LOG "РАСШИРИТЕЛЬ АКТИВЕН!"

PROMPT "РАСШИРИТЕЛЬ АКТИВЕН

Источник: $SOURCE_SSID ✓
Hotspot: $HOTSPOT_SSID
Пароль: $([ \"$SEC_MODE\" -eq 2 ] && echo $HOTSPOT_PASS || echo 'Нет (Открыта)')

Трафик: АКТИВЕН

Нажмите ОК для ОСТАНОВКИ."

# Очистка
killall hostapd dnsmasq wpa_supplicant 2>/dev/null
iptables -t nat -F
iptables -F FORWARD
echo 0 > /proc/sys/net/ipv4/ip_forward

# Удалите виртуальный интерфейс если создан
[ "$AP_IF" = "wlan0_ap" ] && iw dev wlan0_ap del 2>/dev/null

PROMPT "РАСШИРИТЕЛЬ ОСТАНОВЛЕН

Нажмите ОК для выхода."
