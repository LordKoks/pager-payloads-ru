#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
#═══════════════════════════════════════════════════════════════════════════════
# SPECTER — Система бесшумной пассивной электронной разведки
# Разработчик: bad-antics
# 
# Полностью пассивная разведка — не оставляет никаких следов
#═══════════════════════════════════════════════════════════════════════════════

# Подключаем библиотеку
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

source /mmc/nullsec/lib/nullsec-scanner.sh 2>/dev/null

LOOT_DIR="/mmc/nullsec/specter"
mkdir -p "$LOOT_DIR"

PROMPT "    ╔═╗╔═╗╔═╗╔═╗╔╦╗╔═╗╦═╗
    ╚═╗╠═╝║╣ ║   ║ ║╣ ╠╦╝
    ╚═╝╩  ╚═╝╚═╝ ╩ ╚═╝╩╚═
━━━━━━━━━━━━━━━━━━━━━━━━━
СИСТЕМА БЕСШУМНОЙ РАЗВЕДКИ

Режим призрака.
Полностью пассивный сбор данных.
Никаких передаваемых пакетов.

━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics
Нажми OK чтобы начать охоту"

PROMPT "РЕЖИМЫ SPECTER:

1. Теневое наблюдение (пассивно)
2. Шёпотный сбор (probe-запросы)
3. Призрачный профиль (полный)
4. Фантомное отслеживание (следование)

Все режимы полностью БЕСШУМНЫ.
Передача пакетов не происходит."

MODE=$(NUMBER_PICKER "Режим (1-4):" 3)
DURATION=$(NUMBER_PICKER "Длительность (мин):" 5)
DURATION_SEC=$((DURATION * 60))

INTERFACE="$IFACE"
airmon-ng check kill 2>/dev/null
airmon-ng start $INTERFACE >/dev/null 2>&1
MON_IF="${INTERFACE}mon"
[ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"

LOOT_FILE="$LOOT_DIR/specter_$(date +%Y%m%d_%H%M%S).txt"

cat > "$LOOT_FILE" << HEADER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SPECTER — Отчёт бесшумной разведки
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Время: $(date)
 Режим: $MODE
 Длительность: ${DURATION} минут
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HEADER

LOG "Specter активирован..."
SPINNER_START "Режим призрака включён..."

TEMP_DIR="/tmp/specter_$$"
mkdir -p "$TEMP_DIR"

case $MODE in
    1) # Теневое наблюдение — только сети
        timeout $DURATION_SEC airodump-ng $MON_IF -w "$TEMP_DIR/shadow" --output-format csv 2>/dev/null &
        ;;
    2) # Шёпотный сбор — probe-запросы
        timeout $DURATION_SEC airodump-ng $MON_IF -w "$TEMP_DIR/whisper" --output-format csv 2>/dev/null &
        ;;
    3) # Призрачный профиль — полный захват
        timeout $DURATION_SEC airodump-ng $MON_IF -w "$TEMP_DIR/ghost" --output-format csv,pcap 2>/dev/null &
        ;;
    4) # Фантомное отслеживание — прыжки по каналам
        for ch in 1 6 11 2 3 4 5 7 8 9 10; do
            iwconfig $MON_IF channel $ch 2>/dev/null
            timeout 10 tcpdump -i $MON_IF -c 100 -w "$TEMP_DIR/phantom_ch${ch}.pcap" 2>/dev/null
        done &
        ;;
esac

sleep $DURATION_SEC

SPINNER_STOP

# Анализ и формирование отчёта
echo "" >> "$LOOT_FILE"
echo "═══ РАЗВЕДКА СЕТЕЙ ═══" >> "$LOOT_FILE"

AP_COUNT=$(grep -E "^[0-9A-Fa-f]{2}:" "$TEMP_DIR"/*-01.csv 2>/dev/null | grep -v "Station" | wc -l)
CLIENT_COUNT=$(grep -E "^[0-9A-Fa-f]{2}:" "$TEMP_DIR"/*-01.csv 2>/dev/null | grep "Station" -A1000 | grep -E "^[0-9A-Fa-f]{2}:" | wc -l)

echo "Точек доступа: $AP_COUNT" >> "$LOOT_FILE"
echo "Клиентов: $CLIENT_COUNT" >> "$LOOT_FILE"
echo "" >> "$LOOT_FILE"

# Топ сетей
echo "═══ ТОП СЕТЕЙ ═══" >> "$LOOT_FILE"
grep -E "^[0-9A-Fa-f]{2}:" "$TEMP_DIR"/*-01.csv 2>/dev/null | head -20 | while IFS=',' read BSSID F2 F3 CH F5 F6 PRIV F8 F9 PWR F11 F12 F13 ESSID REST; do
    BSSID=$(echo "$BSSID" | tr -d ' ')
    ESSID=$(echo "$ESSID" | tr -d ' ')
    CH=$(echo "$CH" | tr -d ' ')
    PWR=$(echo "$PWR" | tr -d ' ')
    [ -n "$ESSID" ] && echo "  $ESSID ($BSSID) Канал:$CH Сигнал:$PWR" >> "$LOOT_FILE"
done

# Probe-запросы
echo "" >> "$LOOT_FILE"
echo "═══ PROBE-ЗАПРОСЫ ═══" >> "$LOOT_FILE"
grep -A1000 "Station MAC" "$TEMP_DIR"/*-01.csv 2>/dev/null | grep -E "^[0-9A-Fa-f]{2}:" | while IFS=',' read MAC F2 F3 F4 F5 F6 PROBES; do
    MAC=$(echo "$MAC" | tr -d ' ')
    PROBES=$(echo "$PROBES" | tr -d ' ')
    [ -n "$PROBES" ] && echo "  $MAC запрашивал: $PROBES" >> "$LOOT_FILE"
done

# Завершающая часть
cat >> "$LOOT_FILE" << FOOTER

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Конец отчёта SPECTER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FOOTER

# Очистка
airmon-ng stop $MON_IF 2>/dev/null
rm -rf "$TEMP_DIR"

PROMPT "SPECTER ЗАВЕРШЁН
━━━━━━━━━━━━━━━━━━━━━━━━━
Бесшумная разведка завершена.

Сетей: $AP_COUNT
Клиентов: $CLIENT_COUNT

Отчёт: $LOOT_FILE

Передано 0 пакетов.
Следов не оставлено.

━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"