#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: ERROR_DIALOG Example
# Author: Korben
# Description: Example usage of the ERROR_DIALOG DuckyScript command
# Version: 1.0

LOG "Launching error dialog..."
ERROR_DIALOG "Danger to manifold!"