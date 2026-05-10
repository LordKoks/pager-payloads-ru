#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
#═══════════════════════════════════════════════════════════════════════════════
# NullSec Оптимизатор Загрузки
# Разработано: bad-antics
# 
# Оптимизировать время загрузки Pager и производительность во время работы
#═══════════════════════════════════════════════════════════════════════════════

# Автоопределение правильного беспроводного интерфейса (экспортирует $IFACE).
# Возвращается к показу диалога ошибки pager, если ничего не подключено.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

CONFIG_DIR="/mmc/nullsec"
OPTIMIZE_SCRIPT="/etc/init.d/nullsec-optimize"
mkdir -p "$CONFIG_DIR"

PROMPT "⚡ ОПТИМИЗАТОР ЗАГРУЗКИ ⚡
━━━━━━━━━━━━━━━━━━━━━━━━━
Ускорьте ваш Pager

Оптимизируйте время загрузки,
снижайте использование памяти,
быстрее выполнение payload.

━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"

PROMPT "ВАРИАНТЫ ОПТИМИЗАЦИИ:

1. Быстрая Загрузка
   (Пропустить несущественное)

2. Оптимизатор Памяти
   (Освободить RAM)

3. Режим Быстрого WiFi
   (Быстрее сканирование)

4. Полная Оптимизация
   (Все вышеперечисленное)

5. Просмотр Текущего Статуса

6. Сброс к Умолчанию"

CHOICE=$(NUMBER_PICKER "Вариант (1-6):" 4)

optimize_boot() {
    cat > "$OPTIMIZE_SCRIPT" << 'BOOTOPT'
#!/bin/sh /etc/rc.common
# NullSec Оптимизатор Загрузки
START=99
STOP=10

start() {
    # Отключить ненужные сервисы
    /etc/init.d/uhttpd disable 2>/dev/null
    /etc/init.d/dropbear disable 2>/dev/null
    
    # Предварительная загрузка общих инструментов
    which airodump-ng >/dev/null 2>&1
    which aireplay-ng >/dev/null 2>&1
    
    # Установить регулятор CPU на производительность
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    
    logger "Оптимизация загрузки NullSec завершена"
}

stop() {
    echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
}
BOOTOPT
    chmod +x "$OPTIMIZE_SCRIPT"
    "$OPTIMIZE_SCRIPT" enable 2>/dev/null
    LOG "Оптимизация загрузки включена"
}

optimize_memory() {
    # Очистить кэши
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    # Убить ненужные процессы
    pkill -f "uhttpd" 2>/dev/null
    pkill -f "dnsmasq" 2>/dev/null
    
    # Получить статистику памяти
    FREE_MEM=$(free -m | awk '/Mem:/ {print $4}')
    LOG "Память освобождена. Доступно: ${FREE_MEM}MB"
}

optimize_wifi() {
    # Установить WiFi в режим производительности
    iw dev $IFACE set power_save off 2>/dev/null
    
    # Отключить помехи СетьManager
    pkill -f "СетьManager\|wpa_supplicant" 2>/dev/null
    
    # Установить регуляторный домен для макс мощности
    iw reg set US 2>/dev/null
    
    LOG "WiFi оптимизирован для скорости"
}

case $CHOICE in
    1) # Быстрая Загрузка
        SPINNER_START "Оптимизация загрузки..."
        optimize_boot
        SPINNER_STOP
        PROMPT "БЫСТРАЯ ЗАГРУЗКА ВКЛЮЧЕНА
━━━━━━━━━━━━━━━━━━━━━━━━━
Несущественные сервисы
будут пропущены.

Ожидаемое улучшение:
~3-5 секунд быстрее загрузка
━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    2) # Память
        SPINNER_START "Оптимизация памяти..."
        optimize_memory
        SPINNER_STOP
        FREE_MEM=$(free -m 2>/dev/null | awk '/Mem:/ {print $4}' || echo "Н/Д")
        PROMPT "ПАМЯТЬ ОПТИМИЗИРОВАНА
━━━━━━━━━━━━━━━━━━━━━━━━━
Кэши очищены.
Процессы остановлены.

Свободный RAM: ${FREE_MEM}MB
━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    3) # Быстрый WiFi
        SPINNER_START "Оптимизация WiFi..."
        optimize_wifi
        SPINNER_STOP
        PROMPT "РЕЖИМ БЫСТРОГО WIFI
━━━━━━━━━━━━━━━━━━━━━━━━━
Энергосбережение: ВЫКЛ
Помехи: Заблокированы
Рег домен: US (макс мощность)

Сканирование будет быстрее.
━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    4) # Полная оптимизация
        SPINNER_START "Полная оптимизация..."
        optimize_boot
        optimize_memory
        optimize_wifi
        SPINNER_STOP
        FREE_MEM=$(free -m 2>/dev/null | awk '/Mem:/ {print $4}' || echo "Н/Д")
        PROMPT "ПОЛНОСТЬЮ ОПТИМИЗИРОВАНО
━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Загрузка оптимизирована
✓ Память очищена
✓ WiFi в быстром режиме

Свободный RAM: ${FREE_MEM}MB

Ваш Pager теперь
работает на максимальной
производительности.
━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    5) # Статус
        CPU_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "Н/Д")
        FREE_MEM=$(free -m 2>/dev/null | awk '/Mem:/ {print $4}' || echo "Н/Д")
        POWER_SAVE=$(iw dev $IFACE get power_save 2>/dev/null | awk '{print $NF}' || echo "Н/Д")
        PROMPT "СТАТУС СИСТЕМЫ
━━━━━━━━━━━━━━━━━━━━━━━━━
Регулятор CPU: $CPU_GOV
Свободная Память: ${FREE_MEM}MB
Энергосбережение WiFi: $POWER_SAVE
Оптимизатор Загрузки: $([ -f $OPTIMIZE_SCRIPT ] && echo ВКЛ || echo ВЫКЛ)
━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
    6) # Сброс
        CONFIRMATION_DIALOG "Сбросить оптимизации?

Это восстановит
настройки по умолчанию."
        if [ $? -eq 0 ]; then
            rm -f "$OPTIMIZE_SCRIPT"
            echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
            iw dev $IFACE set power_save on 2>/dev/null
            PROMPT "Сброшено к умолчанию.

Рекомендуется перезагрузка."
        fi
        ;;
esac

PROMPT "ОПТИМИЗАЦИЯ ЗАВЕРШЕНА
━━━━━━━━━━━━━━━━━━━━━━━━━
Запускайте этот payload после
каждой перезагрузки для лучшей
производительности.

━━━━━━━━━━━━━━━━━━━━━━━━━
Разработано: bad-antics"
