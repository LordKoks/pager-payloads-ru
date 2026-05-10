#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Название: HandyShake - расширенный алерт захвата хэндшейка
# Author: curtthecoder - github.com/curthayman
# Описание: Комплексный алерт захвата хэндшейка с визуальной/тактильной индикацией, поиском вендора и подробным логированием
# Version: 1.1
# Основано на: handshake-ssid от RootJunky

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

PCAP="$_ALERT_HANDSHAKE_PCAP_PATH"
LOG "HANDYSHAKE: сработало - AP=$_ALERT_HANDSHAKE_AP_MAC_ADDRESS PCAP=$PCAP"
LOG_FILE="/root/loot/handshakes/handshake_log.txt"
CAPTURE_HISTORY="/root/loot/handshakes/capture_history.txt"
ENABLE_VENDOR_LOOKUP=true
ENABLE_GPS_LOGGING=true
ENABLE_AUTO_RENAME=true
RESTORE_LED="R SOLID"       # Цвет/режим LED для восстановления после алерта (напр. "R SOLID", "G SLOW"). Оставьте пустым, чтобы сохранить цвет алерта.

# ============================================================================
# ИЗВЛЕЧЕНИЕ SSID ИЗ PCAP
# ============================================================================

# Сначала пытаемся получить SSID из переменной summary (работает для частичных хэндшейков без Beacon)
SSID=$(echo "$_ALERT_HANDSHAKE_SUMMARY" | sed -n 's/.*SSID[: ]*"\([^"]*\)".*/\1/p' | head -1)

# Резервный вариант: парсинг Beacon-кадров из PCAP (работает для полных хэндшейков)
if [ -z "$SSID" ] && [ -f "$PCAP" ]; then
    SSID=$(tcpdump -r "$PCAP" -e -I -s 256 2>/dev/null \
      | sed -n 's/.*Beacon (\([^)]*\)).*/\1/p' \
      | head -n 1)
fi

[ -n "$SSID" ] || SSID="НЕИЗВЕСТНЫЙ_SSID_Я_НЕ_ЗНАЮ"

# ============================================================================
# ПОИСК ДУБЛИКАТОВ
# ============================================================================

DUPLICATE=false
CAPTURE_KEY="${_ALERT_HANDSHAKE_AP_MAC_ADDRESS}|${_ALERT_HANDSHAKE_CLIENT_MAC_ADDRESS}"

mkdir -p "$(dirname "$CAPTURE_HISTORY")"
touch "$CAPTURE_HISTORY"

if grep -qF "$CAPTURE_KEY" "$CAPTURE_HISTORY" 2>/dev/null; then
    DUPLICATE=true
    LOG "ДУБЛИКАТ: $SSID ($CAPTURE_KEY) уже захвачен - только запись"
fi

echo "${CAPTURE_KEY}|${SSID}|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CAPTURE_HISTORY"

# ============================================================================
# УРОВЕНЬ СИГНАЛА И КАНАЛ
# ============================================================================

RSSI=""
CHANNEL=""

RSSI=$(tcpdump -r "$PCAP" -e -I -s 256 2>/dev/null \
  | sed -n 's/.*[^0-9]\(-[0-9][0-9]*\)dBm signal.*/\1/p' \
  | head -n 1)
[ -n "$RSSI" ] && RSSI="${RSSI}dBm" || RSSI="N/A"

CHANNEL=$(tcpdump -r "$PCAP" -e -I -s 256 2>/dev/null \
  | sed -n 's/.*[^0-9]\([0-9][0-9]*\) MHz.*/\1/p' \
  | head -n 1)
if [ -n "$CHANNEL" ]; then
    case "$CHANNEL" in
        2412) CHANNEL="1" ;; 2417) CHANNEL="2" ;; 2422) CHANNEL="3" ;;
        2427) CHANNEL="4" ;; 2432) CHANNEL="5" ;; 2437) CHANNEL="6" ;;
        2442) CHANNEL="7" ;; 2447) CHANNEL="8" ;; 2452) CHANNEL="9" ;;
        2457) CHANNEL="10" ;; 2462) CHANNEL="11" ;; 2467) CHANNEL="12" ;;
        2472) CHANNEL="13" ;; 2484) CHANNEL="14" ;;
        5180) CHANNEL="36" ;; 5200) CHANNEL="40" ;; 5220) CHANNEL="44" ;;
        5240) CHANNEL="48" ;; 5260) CHANNEL="52" ;; 5280) CHANNEL="56" ;;
        5300) CHANNEL="60" ;; 5320) CHANNEL="64" ;; 5500) CHANNEL="100" ;;
        5520) CHANNEL="104" ;; 5540) CHANNEL="108" ;; 5560) CHANNEL="112" ;;
        5580) CHANNEL="116" ;; 5600) CHANNEL="120" ;; 5620) CHANNEL="124" ;;
        5640) CHANNEL="128" ;; 5660) CHANNEL="132" ;; 5680) CHANNEL="136" ;;
        5700) CHANNEL="140" ;; 5720) CHANNEL="144" ;; 5745) CHANNEL="149" ;;
        5765) CHANNEL="153" ;; 5785) CHANNEL="157" ;; 5805) CHANNEL="161" ;;
        5825) CHANNEL="165" ;;
        *) CHANNEL="${CHANNEL}MHz" ;;
    esac
else
    CHANNEL="N/A"
fi

# ============================================================================
# СЧЁТЧИК ЗАХВАТОВ
# ============================================================================

CAPTURE_COUNT=$(wc -l < "$CAPTURE_HISTORY" 2>/dev/null | tr -d ' ')
[ -n "$CAPTURE_COUNT" ] || CAPTURE_COUNT="1"

# ============================================================================
# ПРОВЕРКА ХЕШ-ФАЙЛА
# ============================================================================

HASH_FILE="$_ALERT_HANDSHAKE_HASHCAT_PATH"
HASH_STATUS="OK"

if [ -z "$HASH_FILE" ] || [ ! -f "$HASH_FILE" ]; then
    HASH_STATUS="MISSING"
elif [ ! -s "$HASH_FILE" ]; then
    HASH_STATUS="EMPTY"
fi

if [ "$HASH_STATUS" = "MISSING" ] && [ -f "$PCAP" ] && command -v hcxpcapngtool >/dev/null 2>&1; then
    RECOVERED_HASH="${PCAP%.pcap}.22000"
    timeout 10 hcxpcapngtool -o "$RECOVERED_HASH" "$PCAP" 2>/dev/null
    if [ -s "$RECOVERED_HASH" ]; then
        HASH_FILE="$RECOVERED_HASH"
        HASH_STATUS="RECOVERED"
        LOG "ВОССТАНОВЛЕНИЕ ХЭША: создан $RECOVERED_HASH из PCAP"
    fi
fi

# ============================================================================
# ПОИСК ВЕНДОРА
# ============================================================================

AP_VENDOR="Неизвестный производитель"
CLIENT_VENDOR="Неизвестный производитель"

if [ "$ENABLE_VENDOR_LOOKUP" = true ]; then
    HAK5_OUI="/root/.hcxtools/oui.txt"

    _oui_file_lookup() {
        local mac="$1"
        [ -f "$HAK5_OUI" ] || return 1
        local oui
        oui=$(echo "$mac" | tr ':' '-' | cut -c1-8 | tr '[:lower:]' '[:upper:]')
        grep -i "^${oui}[[:space:]]*(hex)" "$HAK5_OUI" \
            | sed 's/^[^)]*)[[:space:]]*//' \
            | head -1 | tr -d '\r\n'
    }

    _lookup_vendor() {
        local mac="$1"
        local v=""

        if command -v whoismac >/dev/null 2>&1; then
            v=$(timeout 5 whoismac -m "$mac" 2>/dev/null \
                | grep -i "^VENDOR:" | head -1 \
                | sed 's/^VENDOR: *//;s/ *(UAA[^)]*) *,.*//;s/ *(LAA[^)]*) *,.*//;s/ *([Uu]nicast.*//' \
                | tr -d '\r\n')
        fi

        # Fallback to OUI file if whoismac unavailable or returned nothing
        if [ -z "$v" ] || [ "$v" = "Unknown Vendor" ] || [ "$v" = "Неизвестный производитель" ]; then
            v=$(_oui_file_lookup "$mac")
        fi

        echo "${v:-Неизвестный производитель}"
    }

    AP_VENDOR=$(_lookup_vendor "$_ALERT_HANDSHAKE_AP_MAC_ADDRESS")
    CLIENT_VENDOR=$(_lookup_vendor "$_ALERT_HANDSHAKE_CLIENT_MAC_ADDRESS")

    if [ "$AP_VENDOR" = "Unknown Vendor" ] || [ "$AP_VENDOR" = "Неизвестный производитель" ] || [ "$CLIENT_VENDOR" = "Unknown Vendor" ] || [ "$CLIENT_VENDOR" = "Неизвестный производитель" ]; then
        LOG "ПОИСК ВЕНДОРА: один или несколько производителей неизвестны - база OUI может быть устаревшей. Обновите: cd ~/.hcxtools && rm oui.txt && wget https://standards-oui.ieee.org/oui/oui.txt"
    fi
fi

# ============================================================================
# GPS-КООРДИНАТЫ (если доступны)
# ============================================================================

GPS_DATA=""
if [ "$ENABLE_GPS_LOGGING" = true ]; then
    GPS_INFO=$(timeout 5 GPS_GET 2>/dev/null)
    if [ -n "$GPS_INFO" ] && ! echo "$GPS_INFO" | grep -qE '^[0., ]+$'; then
        GPS_DATA=" | GPS: $GPS_INFO"
    else
        GPS_INFO=""
        GPS_DATA=" | GPS: Нет GPS"
    fi
fi

# ============================================================================
# DEVICE AND СЕТЬ INTELLIGENCE
# ============================================================================

_classify_device() {
    local vendor="$1"
    if echo "$vendor" | grep -qi "amazon"; then
        echo "Устройство Amazon (Echo/Fire TV/Kindle/Ring)"
    elif echo "$vendor" | grep -qi "apple"; then
        echo "Устройство Apple (iPhone/iPad/MacBook/AirPods)"
    elif echo "$vendor" | grep -qi "samsung"; then
        echo "Устройство Samsung (телефон Galaxy/ТВ/планшет)"
    elif echo "$vendor" | grep -qi "google"; then
        echo "Устройство Google (Pixel/Chromecast/Nest)"
    elif echo "$vendor" | grep -qi "roku"; then
        echo "Стриминговое устройство Roku"
    elif echo "$vendor" | grep -qi "sonos"; then
        echo "Колонка Sonos"
    elif echo "$vendor" | grep -qi "ring"; then
        echo "Устройство безопасности Ring (звонок/камера)"
    elif echo "$vendor" | grep -qi "nest"; then
        echo "Устройство Google Nest (термостат/камера/Hub)"
    elif echo "$vendor" | grep -qi "ecobee"; then
        echo "Умный термостат Ecobee"
    elif echo "$vendor" | grep -qi "philips\|signify"; then
        echo "Умное освещение Philips Hue"
    elif echo "$vendor" | grep -qi "tp-link\|tplink"; then
        echo "Устройство TP-Link (роутер/умный дом)"
    elif echo "$vendor" | grep -qi "belkin"; then
        echo "Устройство Belkin (роутер/умный дом WeMo)"
    elif echo "$vendor" | grep -qi "wyze"; then
        echo "Устройство умного дома Wyze (камера/лампочка/розетка)"
    elif echo "$vendor" | grep -qi "eufy"; then
        echo "Устройство безопасности Eufy (камера/дверной звонок)"
    elif echo "$vendor" | grep -qi "arlo"; then
        echo "Камера безопасности Arlo"
    elif echo "$vendor" | grep -qi "bose"; then
        echo "Аудиоустройство Bose"
    elif echo "$vendor" | grep -qi "sony"; then
        echo "Устройство Sony (ТВ/PlayStation/наушники)"
    elif echo "$vendor" | grep -qi "microsoft"; then
        echo "Устройство Microsoft (Surface/Xbox/ноутбук)"
    elif echo "$vendor" | grep -qi "nintendo"; then
        echo "Устройство Nintendo (Switch/игровое)"
    elif echo "$vendor" | grep -qi "xiaomi"; then
        echo "Устройство Xiaomi (телефон/умный дом)"
    elif echo "$vendor" | grep -qi "huawei"; then
        echo "Устройство Huawei (телефон/роутер)"
    elif echo "$vendor" | grep -qi "texas"; then
        echo "Устройство IoT/умного дома (чип Texas Instruments)"
    elif echo "$vendor" | grep -qi "motorola"; then
        echo "Устройство Motorola (телефон)"
    elif echo "$vendor" | grep -qi "lenovo"; then
        echo "Устройство Lenovo (ноутбук/планшет/телефон)"
    elif echo "$vendor" | grep -qi "dell"; then
        echo "Устройство Dell (ноутбук/настольный ПК)"
    elif echo "$vendor" | grep -qi "hewlett\|hp inc"; then
        echo "Устройство HP (ноутбук/принтер)"
    elif echo "$vendor" | grep -qi "cisco"; then
        echo "Устройство Cisco (корпоративное сетевое оборудование)"
    elif echo "$vendor" | grep -qi "aruba"; then
        echo "Устройство Aruba (корпоративное сетевое оборудование)"
    elif echo "$vendor" | grep -qi "ubiquiti"; then
        echo "Устройство Ubiquiti (сетевое оборудование)"
    elif echo "$vendor" | grep -qi "espressif"; then
        echo "IoT-устройство ESP32/ESP8266 (DIY/умный дом)"
    elif echo "$vendor" | grep -qi "raspberry"; then
        echo "Устройство Raspberry Pi"
    elif echo "$vendor" | grep -qi "hon hai\|foxconn"; then
        echo "Устройство Foxconn (Amazon Echo/Fire TV, Nintendo Switch, Sony PlayStation, Vizio TV)"
    elif echo "$vendor" | grep -qi "tonly"; then
        echo "Устройство Tonly Technology (Bluetooth-колонка, саундбар, аудиопродукт TCL)"
    elif echo "$vendor" | grep -qi "altobeam"; then
        echo "Устройство AltoBeam (Smart TV, ТВ-приставка, Android TV)"
    elif echo "$vendor" | grep -qi "tuya"; then
        echo "Устройство Tuya Smart (бытовая техника  возможно, камин)"
    fi
}

_classify_network() {
    local ssid_lower ap_lower
    ssid_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    ap_lower=$(echo "$2" | tr '[:upper:]' '[:lower:]')

    if echo "$ap_lower" | grep -qi "cisco\|aruba\|meraki\|ruckus\|aerohive\|fortinet\|juniper"; then
        echo "Бизнес/корпоративная (точка доступа уровня предприятия)"
    elif echo "$ssid_lower" | grep -qi "corp\|office\|guest\|employee\|staff\|hotel\|cafe\|shop\|store\|restaurant\|bar\|inc\|llc\|ltd"; then
        echo "Вероятно, бизнес/публичная сеть"
    elif echo "$ssid_lower" | grep -qi "verizon_\|xfinity\|spectrum\|att\|optimum\|cox\|myspectrumwifi\|myfiosgateway"; then
        echo "Домашняя/персональная сеть (шлюз от провайдера)"
    elif echo "$ap_lower" | grep -qi "netgear\|linksys\|tp-link\|asus\|belkin\|d-link\|xfinity\|spectrum\|att\|verizon\|comcast\|cox\|google\|eero\|orbi\|synology\|ubiquiti\|unifi\|askey\|sagemcom\|arris\|technicolor\|sercomm"; then
        echo "Домашняя/персональная сеть (потребительский роутер)"
    else
        echo "Неизвестный тип сети"
    fi
}

CLIENT_DEVICE_HINT=$(_classify_device "$CLIENT_VENDOR")
echo "ОТЛАДКА: CLIENT_VENDOR='$CLIENT_VENDOR' HINT='$CLIENT_DEVICE_HINT'" >> /root/loot/handshakes/debug.txt
СЕТЬ_TYPE=$(_classify_network "$SSID" "$AP_VENDOR")

# ============================================================================
# ОПРЕДЕЛЕНИЕ ТИПА И КАЧЕСТВА ХЭНДСХЕЙКА
# ============================================================================

HANDSHAKE_TYPE="$_ALERT_HANDSHAKE_TYPE"
SUMMARY="$_ALERT_HANDSHAKE_SUMMARY"
TYPE_LABEL=""
QUALITY_LABEL=""
CRACK_STATUS=""

if [ "$HANDSHAKE_TYPE" = "eapol" ]; then
    TYPE_LABEL="EAPOL"

    if [ "$_ALERT_HANDSHAKE_COMPLETE" = "true" ]; then
        QUALITY_LABEL="ПОЛНЫЙ"
    else
        QUALITY_LABEL="НЕПОЛНЫЙ"
    fi

    if [ "$_ALERT_HANDSHAKE_CRACKABLE" = "true" ]; then
        CRACK_STATUS="ПОДДАЕТСЯ ВЗЛОМУ"
    else
        CRACK_STATUS="НЕ ПОДДАЕТСЯ ВЗЛОМУ"
    fi

elif [ "$HANDSHAKE_TYPE" = "pmkid" ]; then
    TYPE_LABEL="PMKID"
    QUALITY_LABEL="ОДИН ПАКЕТ"
    CRACK_STATUS="ПОДДАЕТСЯ ВЗЛОМУ"
else
    if echo "$SUMMARY" | grep -qi "pmkid"; then
        HANDSHAKE_TYPE="pmkid"
        TYPE_LABEL="PMKID"
        QUALITY_LABEL="SINGLE PACKET"
    elif echo "$SUMMARY" | grep -q '\[.*[1-4]'; then
        HANDSHAKE_TYPE="eapol"
        TYPE_LABEL="EAPOL"
        if echo "$SUMMARY" | grep -q '\[.*1.*2.*3.*4'; then
            QUALITY_LABEL="ПОЛНЫЙ"
        else
            QUALITY_LABEL="НЕПОЛНЫЙ"
        fi
    else
        TYPE_LABEL="НЕИЗВЕСТНО"
        QUALITY_LABEL="НЕИЗВЕСТНО"
    fi

    if echo "$SUMMARY" | grep -qi "crackable"; then
        CRACK_STATUS="ПОДДАЕТСЯ ВЗЛОМУ"
    elif echo "$SUMMARY" | grep -qi "not crackable\|uncrackable"; then
        CRACK_STATUS="НЕ ПОДДАЕТСЯ ВЗЛОМУ"
    else
        CRACK_STATUS="НЕИЗВЕСТНО"
    fi
fi

# ============================================================================
# АВТО-ПЕРЕИМЕНОВАНИЕ PCAP
# ============================================================================

RENAMED_PCAP=""
if [ "$ENABLE_AUTO_RENAME" = true ] && [ -f "$PCAP" ]; then
    SAFE_SSID=$(echo "$SSID" | sed 's/[^a-zA-Z0-9_-]/_/g' | tr -s '_')
    SAFE_MAC=$(echo "$_ALERT_HANDSHAKE_AP_MAC_ADDRESS" | tr ':' '-')
    FILE_TS=$(date '+%Y%m%d_%H%M%S')
    NEW_NAME="${SAFE_SSID}_${SAFE_MAC}_${FILE_TS}.pcap"
    PCAP_DIR=$(dirname "$PCAP")
    NEW_PATH="${PCAP_DIR}/${NEW_NAME}"

    if cp "$PCAP" "$NEW_PATH" 2>/dev/null; then
        RENAMED_PCAP="$NEW_PATH"
        LOG "АВТО-ПЕРЕИМЕНОВАНИЕ: скопировано в $NEW_NAME"
    fi
fi

# ============================================================================
# VISUAL AND TACTILE FEEDBACK
# ============================================================================

LED_ARGS=""
if [ "$DUPLICATE" = true ]; then
    VIBRATE 50
    LED W SOLID
    LED_ARGS="W SOLID"
else
    if [ "$HANDSHAKE_TYPE" = "eapol" ]; then
        if [ "$_ALERT_HANDSHAKE_COMPLETE" = "true" ] && [ "$_ALERT_HANDSHAKE_CRACKABLE" = "true" ]; then
            VIBRATE 200 100 200 100 200
            LED G SUCCESS
            LED_ARGS="G SUCCESS"
        elif [ "$_ALERT_HANDSHAKE_COMPLETE" = "true" ]; then
            VIBRATE 200 100 200
            LED C SOLID
            LED_ARGS="C SOLID"
        else
            VIBRATE 150 100 150
            LED Y SLOW
            LED_ARGS="Y SLOW"
        fi
    elif [ "$HANDSHAKE_TYPE" = "pmkid" ]; then
        VIBRATE 300
        LED M SOLID
        LED_ARGS="M SOLID"
    else
        VIBRATE 100
        LED Y FAST
        LED_ARGS="Y FAST"
    fi
fi

# ============================================================================
# ОПОВЕЩЕНИЕ
# ============================================================================

DUP_TAG=""
[ "$DUPLICATE" = true ] && DUP_TAG=" [DUP]"

ALERT_MSG="Захват #${CAPTURE_COUNT}${DUP_TAG}: $SSID
$TYPE_LABEL ($QUALITY_LABEL) - $CRACK_STATUS
Сигнал: $RSSI
AP: $_ALERT_HANDSHAKE_AP_MAC_ADDRESS ($AP_VENDOR)
Клиент: $_ALERT_HANDSHAKE_CLIENT_MAC_ADDRESS ($CLIENT_VENDOR)${CLIENT_DEVICE_HINT:+
Подсказка: $CLIENT_DEVICE_HINT}"

ALERT "$ALERT_MSG"
[ -n "$LED_ARGS" ] && LED $LED_ARGS

# ============================================================================
# ЛОГИРОВАНИЕ
# ============================================================================

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "$(dirname "$LOG_FILE")"

cat >> "$LOG_FILE" << EOF
================================================================================
ЗАХВАТ #${CAPTURE_COUNT}: $TIMESTAMP$([ "$DUPLICATE" = true ] && echo " [ДУБЛИКАТ]")
================================================================================
SSID:           $SSID
Тип:            $HANDSHAKE_TYPE ($TYPE_LABEL)
Качество:        $QUALITY_LABEL
Возможность взлома: $CRACK_STATUS
Сигнал:         $RSSI
Канал:          $CHANNEL

AP MAC:         $_ALERT_HANDSHAKE_AP_MAC_ADDRESS
Вендор AP:      $AP_VENDOR

MAC клиента:    $_ALERT_HANDSHAKE_CLIENT_MAC_ADDRESS
Вендор клиента: $CLIENT_VENDOR

Файл PCAP:      ${RENAMED_PCAP:-$_ALERT_HANDSHAKE_PCAP_PATH}
Файл хэшката:   $_ALERT_HANDSHAKE_HASHCAT_PATH (${HASH_STATUS})
${GPS_DATA:+GPS:   ${GPS_INFO:-Нет GPS}}

Тип сети:   $СЕТЬ_TYPE
${CLIENT_DEVICE_HINT:+Подсказка устройства:    $CLIENT_DEVICE_HINT}

Сводка:         $_ALERT_HANDSHAKE_SUMMARY

Последний хэндшейк: "$SSID" ($TYPE_LABEL - $CRACK_STATUS) с $_ALERT_HANDSHAKE_AP_MAC_ADDRESS захвачен $TIMESTAMP
================================================================================

EOF

LOG "ХЭНДСХЕЙК #${CAPTURE_COUNT}: $SSID ($_ALERT_HANDSHAKE_AP_MAC_ADDRESS) - $TYPE_LABEL - $CRACK_STATUS - Ch:$CHANNEL $RSSI$([ "$DUPLICATE" = true ] && echo ' [DUP]')"

# ============================================================================
# СТАТИСТИКА
# ============================================================================

STATS_FILE="/root/loot/handshakes/statistics.txt"

TOTAL_HANDSHAKES=$(find /root/loot/handshakes -type f -name "*.22000" 2>/dev/null | wc -l)
TOTAL_PCAPS=$(find /root/loot/handshakes -type f -name "*.pcap" 2>/dev/null | wc -l)

EAPOL_COUNT=$(grep -c "Тип:.*eapol" "$LOG_FILE" 2>/dev/null); EAPOL_COUNT=${EAPOL_COUNT:-0}
PMKID_COUNT=$(grep -c "Тип:.*pmkid" "$LOG_FILE" 2>/dev/null); PMKID_COUNT=${PMKID_COUNT:-0}
CRACKABLE_COUNT=$(grep -cE "Возможность взлома:.*(ПОДДАЕТСЯ ВЗЛОМУ|CRACKABLE)" "$LOG_FILE" 2>/dev/null); CRACKABLE_COUNT=${CRACKABLE_COUNT:-0}

cat > "$STATS_FILE" << EOF
WiFi Pineapple Pager - Статистика захвата хэндшейков
Последнее обновление: $TIMESTAMP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Всего захватов:      $TOTAL_HANDSHAKES
Всего PCAP:         $TOTAL_PCAPS

Типы захватов:
  - EAPOL:           $EAPOL_COUNT
  - PMKID:           $PMKID_COUNT

Сломаемые:           $CRACKABLE_COUNT

Уникальных AP+Client пар: $(cut -d'|' -f1,2 "$CAPTURE_HISTORY" 2>/dev/null | sort -u | wc -l | tr -d ' ')
Дубликаты:          $(grep -cE "\[(ДУБЛИКАТ|DUPLICATE)\]" "$LOG_FILE" 2>/dev/null || echo 0)

Последний:
  SSID:              $SSID
  AP MAC:            $_ALERT_HANDSHAKE_AP_MAC_ADDRESS
  Тип:               $TYPE_LABEL
  Сигнал:            $RSSI
  Канал:             $CHANNEL
  Статус:            $CRACK_STATUS
  Файл хэша:         $HASH_STATUS
EOF

# ============================================================================
# ЗАВЕРШЕНИЕ
# ============================================================================

[ -n "$RESTORE_LED" ] && LED $RESTORE_LED

exit 0
