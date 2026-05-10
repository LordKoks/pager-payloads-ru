#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: WAIT_FOR_BUTTON_PRESS Example
# Author: Korben
# Description: Example usage of the WAIT_FOR_BUTTON_PRESS DuckyScript command
# Version: 1.0

LOG "Press UP!"
WAIT_FOR_BUTTON_PRESS UP
LOG "User Pressed UP!"