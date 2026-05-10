#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title: Windows Friendly Handshakes
# Description: Payload used to make Handshake files Windows friendly. Gets rid of colons from the filename.
#              Files must be stored in /root/loot/handshakes/
# Author: Skinny
# Version: 1.0

INFOPATH="/root/loot/handshakes"

# if info loot folder does not exist, then create it
LOG "Creating the Info Loot Directory if it doesn't exist."
if [ ! -d "$INFOPATH" ]; then
  mkdir -p "$INFOPATH"
  LOG "Find your file in the newly created $INFOPATH."
else
  LOG "$INFOPATH exists already."
fi

for f in "$INFOPATH"/*:*; do
  mv -- "$f" "${f//:/}"
done


ALERT "Операция завершена"

LOG " "
LOG "OPERATION COMPLETE."
LOG "To see the full results go to $INFOPATH/$FILENAME"
