#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
#═══════════════════════════════════════════════════════════════════════════════
# Библиотека автоопределения интерфейса NullSec
# Автор: bad-antics
#
# Пейджер Pineapple не имеет встроенного радио для разведки — каждый пейлоад
# сканирования/атаки/аудита должен работать с внешним адаптером (MK7AC через
# USB-C является поддерживаемым). Этот адаптер почти никогда не определяется
# как `wlan0`; обычно он отображается как `wlan1` / `wlan1mon`. Пейлоады,
# жестко прописывающие `wlan0`, поэтому "успешно выполняются" с нулевым
# результатом и без ошибок, что сбивает с толку и тратит время.
#
# Эта библиотека предоставляет единственную подключаемую функцию, которая
# выбирает правильный интерфейс один раз и экспортирует $IFACE. Подключите
# её в начале любого пейлоада:
#
#   . /root/payloads/library/nullsec-iface.sh
#   nullsec_require_iface || exit 1
#   # ... далее используйте "$IFACE"
#
# Пользователи могут переопределить, установив IFACE перед запуском, или
# записав /root/.nullsec_env с `export IFACE=wlanX`.
#═══════════════════════════════════════════════════════════════════════════════

NULLSEC_IFACE_VERSION="1.0"

# Загрузка переопределений для конкретного устройства, если присутствуют.
[ -f /root/.nullsec_env ] && . /root/.nullsec_env

# Выбирает лучший интерфейс для разведки/атаки и экспортирует $IFACE.
#
# Приоритет:
#   1. $IFACE, если вызывающий уже установил его и он существует в системе.
#   2. Первый не-loopback беспроводной интерфейс, отличный от wlan0 (внешний).
#   3. wlan0 в крайнем случае (может быть только управляющим на некоторых пейджерах).
#
# Возвращает 0, если пригодный интерфейс найден, иначе 1.
nullsec_detect_iface() {
    # Переопределение, предоставленное вызывающим, имеет приоритет.
    if [ -n "$IFACE" ] && [ -d "/sys/class/net/$IFACE" ]; then
        export IFACE
        return 0
    fi

    # Предпочитаем любой беспроводной интерфейс, который НЕ wlan0.
    local candidate
    # Предпочитаем wlan0mon, если он существует
    if [ -d "/sys/class/net/wlan0mon" ]; then
        export IFACE="wlan0mon"
        return 0
    fi

    for candidate in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        if [ "$candidate" != "wlan0" ] && [ -d "/sys/class/net/$candidate" ]; then
            export IFACE="$candidate"
            return 0
        fi
    done

    # Запасной вариант: wlan0, если он вообще существует.
    if [ -d "/sys/class/net/wlan0" ]; then
        export IFACE="wlan0"
        return 0
    fi

    unset IFACE
    return 1
}

# Обнаружение + вывод дружественного диалога с ошибкой, если ничего
# подходящего не подключено.
# Использует примитивы пользовательского интерфейса пейджера (ERROR_DIALOG /
# PROMPT), когда они доступны, иначе вывод в stderr для CLI/отладки.
nullsec_require_iface() {
    if nullsec_detect_iface; then
        return 0
    fi

    local msg="Внешний беспроводной адаптер не обнаружен.

Подключите ваш MK7AC (или другой USB wifi адаптер) и попробуйте снова.

Пейджер не имеет внутреннего радио для разведки."

    if command -v ERROR_DIALOG >/dev/null 2>&1; then
        ERROR_DIALOG "$msg"
    else
        echo "[nullsec-iface] $msg" >&2
    fi
    return 1
}

# Удобство: убедиться, что $IFACE в режиме монитора, и вывести имя монитора.
# Безопасно вызывать многократно; идемпотентно.
nullsec_ensure_monitor_iface() {
    [ -n "$IFACE" ] || nullsec_detect_iface || return 1

    if iwconfig "$IFACE" 2>/dev/null | grep -q "Режим:Monitor"; then
        echo "$IFACE"
        return 0
    fi

    if [ -d "/sys/class/net/${IFACE}mon" ]; then
        echo "${IFACE}mon"
        return 0
    fi

    airmon-ng check kill >/dev/null 2>&1
    airmon-ng start "$IFACE" >/dev/null 2>&1

    if [ -d "/sys/class/net/${IFACE}mon" ]; then
        echo "${IFACE}mon"
    else
        echo "$IFACE"
    fi
}
