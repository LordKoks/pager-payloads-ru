#!/bin/bash
# Title: Deauth Forensics (Русская версия)
# Author: NullSec
# Description: Анализ атак деаутентификации — идентификация инструментов злоумышленника
# Category: nullsec/blue-team

# ========== FIX: UI PATH и fallback-функции ==========
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Нажмите Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ОШИБКА: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[ЛОГ] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Готово"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Значение: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Выбор: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Подтвердить (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }
# ====================================================

# Autodetect the right wireless interface (exports $IFACE)
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/deauthforensics"
mkdir -p "$LOOT_DIR"

PROMPT "СУДМЕДЭКСПЕРТИЗА DEAUTH

Анализ WiFi-атаки деаутентификации.
Записывает кадры deauth/disassoc
и определяет инструмент атакующего:

- aireplay-ng
- mdk3 / mdk4
- модули Pineapple
- bully / reaver
- собственные скрипты

Также определяет:
- целевой или широковещательный режим
- интенсивность атаки (pps)
- длительность и паттерны
- MAC/OUI атакующего

Нажмите ОК для настройки."

# Проверка интерфейса с поддержкой monitor mode
IFACE=""
for ifc in wlan1mon wlan1 wlan0mon $IFACE; do
    if iw dev "$ifc" info >/dev/null 2>&1; then
        IFACE="$ifc"
        break
    fi
done

if [ -z "$IFACE" ]; then
    ERROR_DIALOG "Нет WiFi интерфейса!

Убедитесь, что адаптер
подключен."
    exit 1
fi

# Проверка tcpdump
if ! command -v tcpdump >/dev/null 2>&1; then
    ERROR_DIALOG "tcpdump не найден!

Установите:
opkg update && opkg install tcpdump"
    exit 1
fi

# Переводим в режим монитора, если нужно
ORIGINAL_MODE=""
if ! echo "$IFACE" | grep -q "mon"; then
    ORIGINAL_MODE="managed"
    ip link set "$IFACE" down 2>/dev/null
    iw dev "$IFACE" set type monitor 2>/dev/null
    ip link set "$IFACE" up 2>/dev/null
    if ! iw dev "$IFACE" info 2>/dev/null | grep -q "monitor"; then
        ERROR_DIALOG "Не удалось включить monitor mode!

Попробуйте: airmon-ng start $IFACE"
        exit 1
    fi
fi

cleanup() {
    kill $CAPTURE_PID 2>/dev/null
    if [ "$ORIGINAL_MODE" = "managed" ]; then
        ip link set "$IFACE" down 2>/dev/null
        iw dev "$IFACE" set type managed 2>/dev/null
        ip link set "$IFACE" up 2>/dev/null
    fi
}
trap cleanup INT TERM EXIT

PROMPT "РЕЖИМ ЗАХВАТА:

1. Один канал
   (фокусированный мониторинг)

2. Перескок каналов
   (сканировать все каналы)

3. Следить за целевой точкой
   (зафиксироваться на конкретной AP)

Интерфейс: $IFACE"

CAP_MODE=$(NUMBER_PICKER "Режим (1-3):" 2)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CAP_MODE=2 ;; esac

if [ $CAP_MODE -eq 1 ]; then
    CHANNEL=$(NUMBER_PICKER "Канал (1-13):" 6)
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) CHANNEL=6 ;; esac
    iw dev "$IFACE" set channel "$CHANNEL" 2>/dev/null
fi

DURATION=$(NUMBER_PICKER "Длительность захвата (мин):" 15)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=15 ;; esac
[ $DURATION -lt 1 ] && DURATION=1
[ $DURATION -gt 120 ] && DURATION=120

resp=$(CONFIRMATION_DIALOG "НАЧАТЬ ЗАХВАТ?

Интерфейс: $IFACE
Режим: $CAP_MODE
Длительность: ${DURATION} мин

Будут захвачены все кадры
деаутентификации и диссоциации
для судебно-медицинского анализа.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

TIMESTAMP=$(date +%Y%m%d_%H%M)
PCAP="$LOOT_DIR/deauth_capture_$TIMESTAMP.pcap"
RAW_LOG="$LOOT_DIR/deauth_raw_$TIMESTAMP.log"
REPORT="$LOOT_DIR/deauth_forensics_$TIMESTAMP.txt"
ATTACKERS="$LOOT_DIR/attackers_$TIMESTAMP.log"
FRAME_DB="/tmp/deauth_frames_$$"
mkdir -p "$FRAME_DB"

SPINNER_START "Захват кадров деаутентификации..."

# Фоновый перескок каналов
if [ $CAP_MODE -eq 2 ]; then
    (
        while true; do
            for ch in 1 6 11 2 3 4 5 7 8 9 10 12 13; do
                iw dev "$IFACE" set channel "$ch" 2>/dev/null
                sleep 0.3
            done
        done
    ) &
    HOPPER_PID=$!
fi

# Захват кадров deauth и disassoc
timeout $((DURATION * 60)) tcpdump -i "$IFACE" -w "$PCAP" \
    'type mgt subtype deauth or type mgt subtype disassoc' \
    2>"$RAW_LOG" &
CAPTURE_PID=$!

# Параллельный анализ в реальном времени
(
    sleep 5
    while kill -0 $CAPTURE_PID 2>/dev/null; do
        if [ -f "$PCAP" ]; then
            tcpdump -r "$PCAP" -n -e -c 10000 2>/dev/null | \
            awk '{
                for(i=1;i<=NF;i++) {
                    if($i ~ /SA:/) sa=$(i+1)
                    if($i ~ /DA:/) da=$(i+1)
                    if($i ~ /Reason/) reason=$(i+1)
                }
                if(sa != "") print sa"|"da"|"reason
            }' >> "$FRAME_DB/all_frames.tmp" 2>/dev/null
        fi
        sleep 10
    done
) &
ANALYZER_PID=$!

wait $CAPTURE_PID 2>/dev/null

[ -n "$HOPPER_PID" ] && kill $HOPPER_PID 2>/dev/null

SPINNER_STOP
SPINNER_START "Анализ захваченных данных..."

# Извлечение всех кадров из pcap
tcpdump -r "$PCAP" -n -e -tttt 2>/dev/null > "$FRAME_DB/decoded.txt"

TOTAL_FRAMES=$(wc -l < "$FRAME_DB/decoded.txt" 2>/dev/null | tr -d ' ')
[ -z "$TOTAL_FRAMES" ] && TOTAL_FRAMES=0

DEAUTH_COUNT=$(grep -ci "deauthentication\|deauth" "$FRAME_DB/decoded.txt" 2>/dev/null || echo 0)
DISASSOC_COUNT=$(grep -ci "disassoc" "$FRAME_DB/decoded.txt" 2>/dev/null || echo 0)

# Уникальные MAC-адреса источников (потенциальные атакующие)
grep -oE "SA:[0-9a-fA-F:]{17}" "$FRAME_DB/decoded.txt" 2>/dev/null | \
    cut -d: -f2- | sort | uniq -c | sort -rn > "$FRAME_DB/sources.txt"

# Уникальные цели
grep -oE "DA:[0-9a-fA-F:]{17}" "$FRAME_DB/decoded.txt" 2>/dev/null | \
    cut -d: -f2- | sort | uniq -c | sort -rn > "$FRAME_DB/targets.txt"

# Коды причин (reason codes)
grep -oE "Reason [0-9]+" "$FRAME_DB/decoded.txt" 2>/dev/null | \
    sort | uniq -c | sort -rn > "$FRAME_DB/reasons.txt"

# ============================================
# ОПРЕДЕЛЕНИЕ ИНСТРУМЕНТА (fingerprinting)
# ============================================
fingerprint_tool() {
    local src_mac="$1"
    local frame_count="$2"
    local tool="НЕИЗВЕСТНО"
    local confidence="НИЗКАЯ"
    local indicators=""

    src_frames=$(grep "$src_mac" "$FRAME_DB/decoded.txt" 2>/dev/null)
    src_count=$(echo "$src_frames" | wc -l)

    reasons=$(echo "$src_frames" | grep -oE "Reason [0-9]+" | sort | uniq -c | sort -rn)
    primary_reason=$(echo "$reasons" | head -1 | awk '{print $2" "$3}')
    reason_variety=$(echo "$reasons" | wc -l)

    targets=$(echo "$src_frames" | grep -oE "DA:[0-9a-fA-F:]{17}" | sort -u | wc -l)

    broadcast_pct=0
    bc_count=$(echo "$src_frames" | grep -ci "ff:ff:ff:ff:ff:ff" || echo 0)
    [ $src_count -gt 0 ] && broadcast_pct=$((bc_count * 100 / src_count))

    # --- Правила определения ---
    if echo "$primary_reason" | grep -q "Reason 7"; then
        if [ $broadcast_pct -lt 30 ]; then
            tool="aireplay-ng"
            confidence="ВЫСОКАЯ"
            indicators="Reason 7 (Class 3 frame), одноадресная рассылка, ровный паттерн"
        fi
    fi

    if [ $broadcast_pct -gt 60 ] && [ $targets -gt 5 ]; then
        tool="mdk3/mdk4"
        confidence="ВЫСОКАЯ"
        indicators="Много широковещательных (${broadcast_pct}%), высокая вариативность целей ($targets целей)"
    fi

    if [ $reason_variety -gt 2 ] && [ $broadcast_pct -gt 40 ]; then
        tool="mdk4 (смешанный режим)"
        confidence="СРЕДНЯЯ"
        indicators="Несколько кодов причин ($reason_variety типов), смесь широковещательных"
    fi

    if echo "$primary_reason" | grep -q "Reason 3"; then
        tool="Модуль WiFi Pineapple"
        confidence="СРЕДНЯЯ"
        indicators="Reason 3 (STA покидает), точечная деаутентификация"
    fi

    if echo "$primary_reason" | grep -q "Reason 7" && [ $targets -le 2 ] && [ $src_count -lt 200 ]; then
        tool="bully/reaver (WPS-атака)"
        confidence="СРЕДНЯЯ"
        indicators="Reason 7, фокус на одной цели ($targets), умеренная скорость — паттерн WPS-брута"
    fi

    if [ $reason_variety -ge 2 ] && [ $targets -ge 3 ] && [ $broadcast_pct -lt 50 ]; then
        tool="wifite/автоматизированный инструмент"
        confidence="СРЕДНЯЯ"
        indicators="Смешанные причины, последовательное переключение целей, автоматизированный паттерн"
    fi

    if [ $broadcast_pct -gt 80 ] && echo "$primary_reason" | grep -q "Reason 1"; then
        tool="Самодельный скрипт деаута"
        confidence="СРЕДНЯЯ"
        indicators="Reason 1 (Неуточнённая), ${broadcast_pct}% широковещательных, массовый флуд"
    fi

    echo "${tool}|${confidence}|${indicators}|${broadcast_pct}|${targets}|${primary_reason}"
}

# Расшифровка кодов причин
decode_reason() {
    case "$1" in
        1) echo "Неуточнённая причина" ;;
        2) echo "Предыдущая аутентификация более не действительна" ;;
        3) echo "STA покидает / покинула" ;;
        4) echo "Неактивность — отключён" ;;
        5) echo "AP не может обслужить всех STA" ;;
        6) echo "Кадр класса 2 от неаутентифицированной STA" ;;
        7) echo "Кадр класса 3 от неассоциированной STA" ;;
        8) echo "STA покидает — отключён" ;;
        9) echo "STA не аутентифицирована" ;;
        10) echo "Неприемлемая мощность" ;;
        11) echo "Неприемлемые поддерживаемые каналы" ;;
        *) echo "Неизвестная причина ($1)" ;;
    esac
}

# Формирование отчёта
cat > "$REPORT" << HEADER
==========================================
    NULLSEC СУДМЕДЭКСПЕРТИЗА DEAUTH
==========================================

Время захвата: $(date)
Длительность: ${DURATION} мин
Интерфейс: $IFACE
Режим захвата: $CAP_MODE
PCAP файл: $PCAP

============ СВОДКА ПО КАДРАМ ==============

Всего кадров: $TOTAL_FRAMES
Деаутентификация:      $DEAUTH_COUNT
Диссоциация:           $DISASSOC_COUNT

HEADER

# Анализ атакующих
echo "========== АНАЛИЗ АТАКУЮЩИХ ==========" >> "$REPORT"
echo >> "$REPORT"

ATTACKER_NUM=0
while read -r count mac; do
    [ -z "$mac" ] && continue
    ATTACKER_NUM=$((ATTACKER_NUM + 1))

    OUI=$(echo "$mac" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]')

    FP=$(fingerprint_tool "$mac" "$count")
    TOOL=$(echo "$FP" | cut -d'|' -f1)
    CONF=$(echo "$FP" | cut -d'|' -f2)
    INDICATORS=$(echo "$FP" | cut -d'|' -f3)
    BC_PCT=$(echo "$FP" | cut -d'|' -f4)
    TGT_COUNT=$(echo "$FP" | cut -d'|' -f5)
    PRI_REASON=$(echo "$FP" | cut -d'|' -f6)

    cat >> "$REPORT" << ATTACKER
--- Атакующий #$ATTACKER_NUM ---
MAC источника:      $mac
Префикс OUI:        $OUI
Кадров отправлено:  $count
Широковещательных %:${BC_PCT}%
Уникальных целей:   $TGT_COUNT
Первичная причина:  $PRI_REASON

ОПРЕДЕЛЕНИЕ ИНСТРУМЕНТА: $TOOL
Уверенность:          $CONF
Признаки:             $INDICATORS

ATTACKER

    echo "[$ATTACKER_NUM] $mac | $count кадров | Инструмент: $TOOL ($CONF) | Целей: $TGT_COUNT" >> "$ATTACKERS"

done < "$FRAME_DB/sources.txt"

echo >> "$REPORT"
echo "============ АНАЛИЗ ЦЕЛЕЙ ============" >> "$REPORT"
echo >> "$REPORT"
echo "Наиболее атакуемые устройства:" >> "$REPORT"
head -10 "$FRAME_DB/targets.txt" >> "$REPORT" 2>/dev/null

echo >> "$REPORT"
echo "=========== КОДЫ ПРИЧИН ================" >> "$REPORT"
echo >> "$REPORT"
while read -r count reason_str; do
    [ -z "$count" ] && continue
    reason_num=$(echo "$reason_str" | grep -oE "[0-9]+")
    decoded=$(decode_reason "$reason_num")
    echo "$count x $reason_str — $decoded" >> "$REPORT"
done < "$FRAME_DB/reasons.txt"

echo >> "$REPORT"
echo "==========================================" >> "$REPORT"
echo "Сгенерировано NullSec DeauthForensics" >> "$REPORT"
echo "$(date)" >> "$REPORT"

# Очистка
kill $ANALYZER_PID 2>/dev/null
rm -rf "$FRAME_DB"

SPINNER_STOP

# Отображение результатов на экране Pager'а
TOP_ATTACKER_MAC=$(head -1 "$FRAME_DB/sources.txt" 2>/dev/null | awk '{print $2}')
TOP_ATTACKER_FP=$(head -1 "$ATTACKERS" 2>/dev/null)

PROMPT "СУДМЕДЭКСПЕРТИЗА DEAUTH ЗАВЕРШЕНА

Всего кадров: $TOTAL_FRAMES
Деаутов: $DEAUTH_COUNT
Диссоциаций: $DISASSOC_COUNT

Найдено атакующих: $ATTACKER_NUM

Нажмите OK для деталей."

if [ -f "$ATTACKERS" ]; then
    ATTACKER_DETAILS=$(cat "$ATTACKERS" 2>/dev/null | head -5)
    PROMPT "СВОДКА ПО АТАКУЮЩИМ

$ATTACKER_DETAILS

Нажмите OK для информации о файлах."
fi

PROMPT "ФАЙЛЫ СОХРАНЕНЫ

PCAP захват:
deauth_capture_$TIMESTAMP.pcap

Отчёт криминалистики:
deauth_forensics_$TIMESTAMP.txt

Лог атакующих:
attackers_$TIMESTAMP.log

Расположение: $LOOT_DIR/

Импортируйте PCAP в Wireshark
для более глубокого анализа.

Нажмите OK для выхода."

exit 0
