#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title:                Route
# Description:          Lists routing table information and logs the results
# Author:               tototo31
# Version:              1.0

# Options
LOOTDIR=/root/loot/route
DEFAULT_VIEW="all"

# === UTILITIES ===

setup() {
    LED SETUP
    # Check for ip command (preferred, modern)
    if ! command -v ip >/dev/null 2>&1; then
        LOG "Installing iproute2..."
        opkg update
        opkg install iproute2
        if ! command -v ip >/dev/null 2>&1; then
            # Fall back to checking for route command
            if ! command -v route >/dev/null 2>&1; then
                LOG "Installing net-tools..."
                opkg install net-tools
                if ! command -v route >/dev/null 2>&1; then
                    LED FAIL
                    LOG "ERROR: Failed to install route utilities"
                    ERROR_DIALOG "Route utilities installation failed. Cannot list routing information."
                    LOG "Exiting - route utilities are required but could not be установлен"
                    exit 1
                fi
            fi
        fi
    fi
}

# === MAIN ===

# Setup and check dependencies
setup

# Determine which command to use (prefer ip over route)
if command -v ip >/dev/null 2>&1; then
    USE_IP_CMD=true
else
    USE_IP_CMD=false
fi

# Prompt user for view type
LOG "Запускаю Route..."
LOG "Выберите тип просмотра:"
LOG "1. Все маршруты (по умолчанию)"
LOG "2. Только IPv4 маршруты"
LOG "3. Только IPv6 маршруты"
LOG "4. Только маршрут по умолчанию"
LOG "5. Маршруты для конкретного интерфейса"
LOG ""
LOG "Нажмите кнопку A, чтобы продолжить..."

WAIT_FOR_BUTTON_PRESS A

view_choice=$(NUMBER_PICKER "Выберите тип просмотра (1-5)" 1)
case $? in
    $DUCKYSCRIPT_CANCELLED)
        LOG "Пользователь отменил"
        exit 1
        ;;
    $DUCKYSCRIPT_REJECTED)
        LOG "Использую вид по умолчанию: все маршруты"
        view_choice=1
        ;;
    $DUCKYSCRIPT_ERROR)
        LOG "Произошла ошибка, использую вид по умолчанию: все маршруты"
        view_choice=1
        ;;
esac

# Determine route options based on view choice
case $view_choice in
    1)
        view_name="all"
        if [ "$USE_IP_CMD" = true ]; then
            route_cmd="ip route show"
        else
            route_cmd="route -n"
        fi
        ;;
    2)
        view_name="ipv4"
        if [ "$USE_IP_CMD" = true ]; then
            route_cmd="ip -4 route show"
        else
            route_cmd="route -n -4"
        fi
        ;;
    3)
        view_name="ipv6"
        if [ "$USE_IP_CMD" = true ]; then
            route_cmd="ip -6 route show"
        else
            route_cmd="route -n -6"
        fi
        ;;
    4)
        view_name="default"
        if [ "$USE_IP_CMD" = true ]; then
            route_cmd="ip route show default"
        else
            route_cmd="route -n | grep '^0.0.0.0'"
        fi
        ;;
    5)
        # Get list of interfaces
        if [ "$USE_IP_CMD" = true ]; then
            interfaces=$(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | awk -F'@' '{print $1}')
        elif command -v ifconfig >/dev/null 2>&1; then
            interfaces=$(ifconfig -a | grep -E '^[a-z]' | awk '{print $1}' | sed 's/:$//')
        else
            # Fallback to /proc/net/dev (always available on Linux)
            interfaces=$(cat /proc/net/dev | grep -E '^[[:space:]]*[a-z]' | awk -F':' '{print $1}' | tr -d ' ')
        fi
        
        if [ -z "$interfaces" ]; then
            LOG "ОШИБКА: Сетевые интерфейсы не найдены"
            ERROR_DIALOG "Сетевые интерфейсы не найдены. Невозможно отфильтровать по интерфейсу."
            exit 1
        fi
        
        # Store interfaces in array for indexing
        interface_array=()
        interface_count=0
        while IFS= read -r iface; do
            if [ -n "$iface" ]; then
                interface_array+=("$iface")
                interface_count=$((interface_count + 1))
            fi
        done <<< "$interfaces"
        
        # Create interface selection dialog
        LOG "Выберите интерфейс:"
        for i in $(seq 1 $interface_count); do
            idx=$((i - 1))
            LOG "$i. ${interface_array[$idx]}"
        done
        LOG ""
        LOG "Нажмите кнопку A, чтобы продолжить..."
        
        WAIT_FOR_BUTTON_PRESS A
        
        interface_choice=$(NUMBER_PICKER "Выберите интерфейс (1-$interface_count)" 1)
        case $? in
            $DUCKYSCRIPT_CANCELLED)
                LOG "Пользователь отменил"
                exit 1
                ;;
            $DUCKYSCRIPT_REJECTED)
                LOG "Использую по умолчанию: первый интерфейс"
                interface_choice=1
                ;;
            $DUCKYSCRIPT_ERROR)
                LOG "Произошла ошибка, использую по умолчанию: первый интерфейс"
                interface_choice=1
                ;;
        esac
        
        # Validate choice and get interface name
        if [ "$interface_choice" -lt 1 ] || [ "$interface_choice" -gt "$interface_count" ]; then
            LOG "Неверный выбор, использую первый интерфейс"
            interface_choice=1
        fi
        
        idx=$((interface_choice - 1))
        interface="${interface_array[$idx]}"
        
        view_name="interface_${interface}"
        if [ "$USE_IP_CMD" = true ]; then
            route_cmd="ip route show dev $interface"
        else
            route_cmd="route -n | grep $interface"
        fi
        ;;
    *)
        LOG "Неверный выбор, использую по умолчанию: все маршруты"
        view_name="all"
        if [ "$USE_IP_CMD" = true ]; then
            route_cmd="ip route show"
        else
            route_cmd="route -n"
        fi
        ;;
esac

# Create loot destination if needed
mkdir -p $LOOTDIR
lootfile=$LOOTDIR/$(date -Is)_route_${view_name}

LOG "Показ таблицы маршрутизации (вид: $view_name)..."
LOG "Результаты будут сохранены в: $lootfile\n"

# Run route command and capture output
LED ATTACK
route_output=$(eval "$route_cmd" 2>&1)

# Save output to file
echo "$route_output" > $lootfile

# Check if output is empty (trim whitespace)
route_output_trimmed=$(echo "$route_output" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -z "$route_output_trimmed" ]; then
    LOG "Информация о маршрутах для этого вида не найдена."
    LOG "Таблица маршрутизации может быть пуста или фильтр не вернул результатов."
    ALERT "Информация о маршрутах недоступна"
else
    # Display the route output
    echo "$route_output" | sed G | tr '\n' '\0' | xargs -0 -n 1 LOG
fi

LOG "\nПоказ маршрутов завершён!"

