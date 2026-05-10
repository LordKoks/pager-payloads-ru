#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Firewall Manager
# Author: NullSec
# Description: Manage iptables firewall rules from the Pager UI
# Category: nullsec/utility

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Value: " val; echo "$val"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

LOOT_DIR="/mmc/nullsec/firewall"
mkdir -p "$LOOT_DIR"

PROMPT "МЕНЕДЖЕР ФАЙЕРВОЛА

Управляйте правилами iptables
из интерфейса Pager.

Функции:
- Блокировка/разрешение клиентов
- Управление портами
- Фильтрация протоколов
- Просмотр активных правил
- Сохранение/восстановление правил

Нажмите OK, чтобы продолжить."

# Check iptables
if ! command -v iptables >/dev/null 2>&1; then
    ERROR_DIALOG "iptables не найден!

Установите:
opkg install iptables"
    exit 1
fi

# Get current rule count
RULE_COUNT=$(iptables -L -n 2>/dev/null | grep -c "^[A-Z]")
NAT_COUNT=$(iptables -t nat -L -n 2>/dev/null | grep -c "^[A-Z]")

PROMPT "СТАТУС ФАЙЕРВОЛА

Активных правил: $RULE_COUNT
NAT правил: $NAT_COUNT

ОПЕРАЦИЯ:
1. Заблокировать IP клиента
2. Заблокировать порт
3. Разрешить порт
4. Заблокировать протокол
5. Просмотреть текущие правила
6. Сбросить все правила
7. Сохранить правила
8. Восстановить правила

Выберите операцию."

OPERATION=$(NUMBER_PICKER "Операция (1-8):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) OPERATION=1 ;; esac

case $OPERATION in
    1) # Block client IP
        # Scan for clients
        SPINNER_START "Сканирование клиентов..."
        CLIENTS=$(arp -an 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
        CLIENT_COUNT=$(echo "$CLIENTS" | wc -l)
        SPINNER_STOP

        PROMPT "ПОДКЛЮЧЕННЫХ КЛИЕНТОВ: $CLIENT_COUNT

$(echo "$CLIENTS" | head -8)

Нажмите OK, чтобы ввести IP."

        BLOCK_IP=$(TEXT_PICKER "IP для блокировки:" "$(echo "$CLIENTS" | head -1)")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        PROMPT "НАПРАВЛЕНИЕ БЛОКИРОВКИ:

1. Блокировать весь трафик
2. Блокировать только исходящий
3. Блокировать только входящий

Выберите направление."

        DIRECTION=$(NUMBER_PICKER "Направление (1-3):" 1)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DIRECTION=1 ;; esac

        resp=$(CONFIRMATION_DIALOG "БЛОКИРОВАТЬ $BLOCK_IP?

Направление: $(case $DIRECTION in 1) echo "Всё";; 2) echo "Исходящий";; 3) echo "Входящий";; esac)

Изменения вступят в силу
немедленно.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Добавление правила..."
        case $DIRECTION in
            1) iptables -A FORWARD -s "$BLOCK_IP" -j DROP 2>/dev/null
               iptables -A FORWARD -d "$BLOCK_IP" -j DROP 2>/dev/null ;;
            2) iptables -A FORWARD -s "$BLOCK_IP" -j DROP 2>/dev/null ;;
            3) iptables -A FORWARD -d "$BLOCK_IP" -j DROP 2>/dev/null ;;
        esac
        SPINNER_STOP

        echo "$(date) | BLOCK | $BLOCK_IP | dir=$DIRECTION" >> "$LOOT_DIR/firewall.log"
        LOG "Blocked $BLOCK_IP"

        PROMPT "КЛИЕНТ ЗАБЛОКИРОВАН

$BLOCK_IP теперь заблокирован.

Для разблокировки сбросьте правила
или перезапустите устройство.

Нажмите OK, чтобы выйти."
        ;;

    2) # Block port
        PORT=$(NUMBER_PICKER "Порт для блокировки:" 80)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        PROMPT "ПРОТОКОЛ:

1. Только TCP
2. Только UDP
3. TCP и UDP

Выберите протокол."

        PROTO=$(NUMBER_PICKER "Протокол (1-3):" 3)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PROTO=3 ;; esac

        resp=$(CONFIRMATION_DIALOG "ЗАБЛОКИРОВАТЬ ПОРТ $PORT?

Протокол: $(case $PROTO in 1) echo TCP;; 2) echo UDP;; 3) echo "TCP+UDP";; esac)

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Блокировка порта $PORT..."
        case $PROTO in
            1) iptables -A FORWARD -p tcp --dport "$PORT" -j DROP 2>/dev/null ;;
            2) iptables -A FORWARD -p udp --dport "$PORT" -j DROP 2>/dev/null ;;
            3) iptables -A FORWARD -p tcp --dport "$PORT" -j DROP 2>/dev/null
               iptables -A FORWARD -p udp --dport "$PORT" -j DROP 2>/dev/null ;;
        esac
        SPINNER_STOP

        echo "$(date) | BLOCK_PORT | $PORT | proto=$PROTO" >> "$LOOT_DIR/firewall.log"

        PROMPT "ПОРТ $PORT ЗАБЛОКИРОВАН

Правило добавлено в цепочку FORWARD.

Нажмите OK, чтобы выйти."
        ;;

    3) # Allow port
        PORT=$(NUMBER_PICKER "Порт для разрешения:" 443)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        SPINNER_START "Разрешение порта $PORT..."
        iptables -I FORWARD -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
        iptables -I FORWARD -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
        SPINNER_STOP

        echo "$(date) | ALLOW_PORT | $PORT" >> "$LOOT_DIR/firewall.log"

        PROMPT "ПОРТ $PORT РАЗРЕШЕН

Правило вставлено в начало
цепочки FORWARD.

Нажмите OK, чтобы выйти."
        ;;

    4) # Block protocol
        PROMPT "ЗАБЛОКИРОВАТЬ ПРОТОКОЛ:

1. ICMP (ping)
2. GRE (VPN туннели)
3. ESP (IPSec)
4. Весь UDP

Выберите протокол."

        BLOCK_PROTO=$(NUMBER_PICKER "Протокол (1-4):" 1)
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        resp=$(CONFIRMATION_DIALOG "ЗАБЛОКИРОВАТЬ ПРОТОКОЛ?

$(case $BLOCK_PROTO in 1) echo "ICMP (ping)";; 2) echo "GRE (VPN туннели)";; 3) echo "ESP (IPSec)";; 4) echo "Весь UDP";; esac)

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Блокировка протокола..."
        case $BLOCK_PROTO in
            1) iptables -A FORWARD -p icmp -j DROP 2>/dev/null ;;
            2) iptables -A FORWARD -p gre -j DROP 2>/dev/null ;;
            3) iptables -A FORWARD -p esp -j DROP 2>/dev/null ;;
            4) iptables -A FORWARD -p udp -j DROP 2>/dev/null ;;
        esac
        SPINNER_STOP

        echo "$(date) | BLOCK_PROTO | $BLOCK_PROTO" >> "$LOOT_DIR/firewall.log"

        PROMPT "ПРОТОКОЛ ЗАБЛОКИРОВАН

Правило применено.

Нажмите OK, чтобы выйти."
        ;;

    5) # View rules
        SPINNER_START "Чтение правил..."
        RULES=$(iptables -L -n --line-numbers 2>/dev/null | head -20)
        RULE_COUNT=$(iptables -L -n 2>/dev/null | grep -cE "^(ACCEPT|DROP|REJECT)")
        SPINNER_STOP

        PROMPT "ПРАВИЛА ФАЙЕРВОЛА ($RULE_COUNT)

$(echo "$RULES" | head -15)

Нажмите OK, чтобы выйти."
        ;;

    6) # Flush rules
        resp=$(CONFIRMATION_DIALOG "СБРОСИТЬ ВСЕ ПРАВИЛА?

ВНИМАНИЕ: Это удалит
все правила файервола!

Сеть станет открытой
без фильтрации.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        # Save before flushing
        iptables-save > "$LOOT_DIR/backup_$(date +%Y%m%d_%H%M).rules" 2>/dev/null

        SPINNER_START "Сброс правил..."
        iptables -F 2>/dev/null
        iptables -t nat -F 2>/dev/null
        iptables -X 2>/dev/null
        iptables -P FORWARD ACCEPT 2>/dev/null
        SPINNER_STOP

        echo "$(date) | FLUSH_ALL" >> "$LOOT_DIR/firewall.log"

        PROMPT "ПРАВИЛА СБРОШЕНЫ

Все правила удалены.
Резервная копия сохранена в
$LOOT_DIR/

Нажмите OK, чтобы выйти."
        ;;

    7) # Save ruleset
        SPINNER_START "Сохранение набора правил..."
        SAVE_FILE="$LOOT_DIR/rules_$(date +%Y%m%d_%H%M).rules"
        iptables-save > "$SAVE_FILE" 2>/dev/null
        SPINNER_STOP

        PROMPT "НАБОР ПРАВИЛ СОХРАНЕН

Файл: $SAVE_FILE

Нажмите OK, чтобы выйти."
        ;;

    8) # Restore ruleset
        RULESETS=$(ls "$LOOT_DIR"/*.rules 2>/dev/null | tail -5)
        [ -z "$RULESETS" ] && { ERROR_DIALOG "Сохранённых наборов правил не найдено!"; exit 1; }

        PROMPT "СОХРАНЁННЫЕ НАБОРЫ ПРАВИЛ:

$(basename -a $RULESETS 2>/dev/null)

Введите имя файла."

        RESTORE_FILE=$(TEXT_PICKER "Имя файла:" "$(basename $(echo "$RULESETS" | tail -1))")
        case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;; esac

        FULL_PATH="$LOOT_DIR/$RESTORE_FILE"
        [ ! -f "$FULL_PATH" ] && { ERROR_DIALOG "Файл не найден: $RESTORE_FILE"; exit 1; }

        resp=$(CONFIRMATION_DIALOG "ВОССТАНОВИТЬ ПРАВИЛА?

Файл: $RESTORE_FILE

Это заменит текущую
конфигурацию файервола.

Подтвердить?")
        [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

        SPINNER_START "Восстановление правил..."
        iptables-restore < "$FULL_PATH" 2>/dev/null
        SPINNER_STOP

        echo "$(date) | RESTORE | $RESTORE_FILE" >> "$LOOT_DIR/firewall.log"

        PROMPT "ПРАВИЛА ВОССТАНОВЛЕНЫ

Загружено: $RESTORE_FILE

Нажмите OK, чтобы выйти."
        ;;
esac
