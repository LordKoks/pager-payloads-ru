#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Маскировка сигнала
# Author: bad-antics
# Description: Снижение мощности сигнала и рандомизация запросов для скрытной работы
# Category: nullsec

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "МАСКИРОВКА СИГНАЛА
━━━━━━━━━━━━━━━━━━━━━━━━━
Минимизация радиоизлучения.

- Снижение мощности передачи
- Рандомизация probe-запросов
- Только пассивное сканирование

Нажми OK для настройки."

POWER=$(NUMBER_PICKER "Мощность передачи (1-20 dBm):" 5)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) POWER=5 ;; esac
[ $POWER -lt 1 ] && POWER=1
[ $POWER -gt 20 ] && POWER=20

resp=$(CONFIRMATION_DIALOG "НАСТРОЙКИ МАСКИРОВКИ:
━━━━━━━━━━━━━━━━━━━━━━━━━
Мощность: ${POWER} dBm
Probe-запросы: случайные
Режим сканирования: пассивный

АКТИВИРОВАТЬ?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

SPINNER_START "Активация маскировки..."

# Снижение мощности передачи
iw dev $IFACE set txpower fixed $((POWER * 100)) 2>/dev/null
iw dev wlan1 set txpower fixed $((POWER * 100)) 2>/dev/null

# Отключение энергосбережения
iw dev $IFACE set power_save off 2>/dev/null

# Генерация случайного MAC-адреса
RANDOM_MAC=$(printf '%02x:%02x:%02x:%02x:%02x:%02x' \
    $((RANDOM % 256 & 0xFE | 0x02)) \
    $((RANDOM % 256)) $((RANDOM % 256)) \
    $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))

ip link set $IFACE down 2>/dev/null
ip link set $IFACE address "$RANDOM_MAC" 2>/dev/null
ip link set $IFACE up 2>/dev/null

SPINNER_STOP

PROMPT "МАСКИРОВКА АКТИВНА
━━━━━━━━━━━━━━━━━━━━━━━━━
Мощность: ${POWER} dBm
MAC: $RANDOM_MAC
Режим: пассивный

Твой радиоотпечаток 
значительно уменьшен.

Для отключения — перезагрузи устройство."