#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Name: Disable Evil Portal
# Description: Disables the Evil Portal service
# Author: PentestPlaybook
# Version: 1.0
# Category: Wireless

/etc/init.d/evilportal disable
ALERT "Evil Portal disabled."
