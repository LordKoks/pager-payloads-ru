#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Targeted AP HackStats
# Author: Unit981
# Description: Get handshake and pcap stats for selected AP
# Version: 1.1

#Setting directory
HANDSHAKE_DIR="/root/loot/handshakes/"

#Making sure BSSID/MAC is searchable
bssid_clean=$(printf "%s" "$_RECON_SELECTED_AP_BSSID" | sed 's/[[:space:]]//g')
bssid_upper=${bssid_clean^^}

#Count files containing MAC anywhere in the filename
handshake_count=$(find "$HANDSHAKE_DIR" -type f -name "*${bssid_upper}*.22000" 2>/dev/null | wc -l)
pcap_count=$(find "$HANDSHAKE_DIR" -type f -name "*${bssid_upper}*.pcap" 2>/dev/null | wc -l)

#Final output
ALERT "#@ ВЗЛОМАЙТЕ ПЛАНЕТУ @# \n\n SSID AP: $_RECON_SELECTED_AP_SSID \n AP BSSID: $_RECON_SELECTED_AP_BSSID \n Handshake Count: $handshake_count \n PCAP Count: $pcap_count"

