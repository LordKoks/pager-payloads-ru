# ICMP Alert
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
- Description: Alert the wifi pineapple pager of ping or traceroute then Disabling incoming ICMP/UDP for 60 seconds
