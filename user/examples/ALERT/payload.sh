#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: ALERT Example
# Author: Korben
# Description: Example usage of the ALERT DuckyScript command
# Version: 1.0

LOG "Launching alert..."
ALERT "Hack the planet!"