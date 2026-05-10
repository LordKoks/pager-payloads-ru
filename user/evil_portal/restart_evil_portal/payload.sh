#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Name: Restart Evil Portal
# Description: Restarts the Evil Portal service
# Author: PentestPlaybook
# Version: 1.0
# Category: Wireless

/etc/init.d/evilportal restart
ALERT "Evil Portal restarted"
