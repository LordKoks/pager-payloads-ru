#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: LOG Example
# Author: Korben
# Description: Example usage of the LOG DuckyScript command
# Version: 1.0

LOG red "Hello, World!"
LOG green "Hello, World!"
LOG blue "Hello, World!"
LOG "Hello, World!"
