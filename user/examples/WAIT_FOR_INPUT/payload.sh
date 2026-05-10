#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: WAIT_FOR_INPUT Example
# Author: Korben
# Description: Example usage of the WAIT_FOR_INPUT DuckyScript command
# Version: 1.0

LOG "Нажмите любую кнопку!"
resp=$(WAIT_FOR_INPUT)
LOG "User pressed: $resp"