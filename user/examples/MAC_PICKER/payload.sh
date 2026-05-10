#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: MAC_PICKER Example
# Author: Korben
# Description: Example usage of the MAC_PICKER DuckyScript command
# Version: 1.0

LOG "Launching MAC picker..."
resp=$(MAC_PICKER "Target MAC?" "DE:AD:BE:EF:CA:FE")
case $? in
    $DUCKYSCRIPT_CANCELLED)
        LOG "User cancelled"
        exit 1
        ;;
    $DUCKYSCRIPT_REJECTED)
        LOG "Dialog rejected"
        exit 1
        ;;
    $DUCKYSCRIPT_ERROR)
        LOG "An error occurred"
        exit 1
        ;;
esac

LOG "User Picked $resp"
