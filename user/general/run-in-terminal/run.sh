#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# run_pager_payload.sh

PAYLOAD="$1"

if [ -z "$PAYLOAD" ] || [ ! -f "$PAYLOAD" ]; then
  echo "Использование: $0 payload.sh"
  exit 1
fi

echo "[+] Загружаю Pager Ducky shim"
source /usr/bin/pager_ducky_shim.sh

echo "[+] Запуск payload: $PAYLOAD"
echo "--------------------------------"

bash "$PAYLOAD"

echo "--------------------------------"
echo "[✓] Payload завершён"
exit 0
