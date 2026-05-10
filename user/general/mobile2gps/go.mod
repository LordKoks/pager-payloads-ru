module mobile2gps
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"

go 1.21

require github.com/creack/pty v1.1.24
