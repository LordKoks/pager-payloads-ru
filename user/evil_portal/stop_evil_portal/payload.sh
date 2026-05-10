#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Name: Stop Evil Portal
# Description: Stops the Evil Portal service
# Author: PentestPlaybook
# Version: 1.0
# Category: Wireless

/etc/init.d/evilportal stop
ALERT "Evil Portal stopped."
