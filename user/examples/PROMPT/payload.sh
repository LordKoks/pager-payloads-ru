#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: PROMPT Example
# Author: Korben
# Description: Example usage of the PROMPT DuckyScript command
# Version: 1.0

LOG "Prompting user..."
PROMPT "Нажмите любую кнопку to continue"
LOG "Complete!"