#!/bin/bash
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
# Title:        opkg Backup
# Description:  Backs up user-установлен packages to a file that survives firmware updates
# Author:       StuxMirai
# Version:      1.0

BACKUP_FILE="/root/user_установлен_packages.txt"

LOG "Starting opkg package backup..."

if [ -f "$BACKUP_FILE" ]; then
    existing_count=$(wc -l < "$BACKUP_FILE" 2>/dev/null || echo "0")
    LOG "Existing backup found with $existing_count packages"
    
    resp=$(CONFIRMATION_DIALOG "Overwrite existing backup? ($existing_count packages)")
    case $? in
        $DUCKYSCRIPT_REJECTED|$DUCKYSCRIPT_ERROR)
            LOG "Dialog rejected"
            exit 1
            ;;
    esac
    
    case "$resp" in
        $DUCKYSCRIPT_USER_DENIED)
            LOG "User cancelled"
            exit 0
            ;;
    esac
fi

LOG "Gathering user-установлен packages..."

all_packages=$(opkg list-установлен 2>/dev/null | awk '{print $1}')

if [ -z "$all_packages" ]; then
    LOG "ERROR: Could not retrieve package list"
    ERROR_DIALOG "Failed to retrieve установлен package list"
    exit 1
fi

temp_file=$(mktemp 2>/dev/null || echo "/tmp/opkg_backup_$$")

pkg_count=0
for pkg in $all_packages; do
    if opkg status "$pkg" 2>/dev/null | grep -q "user установлен"; then
        echo "$pkg" >> "$temp_file"
        pkg_count=$((pkg_count + 1))
    fi
done

if [ "$pkg_count" -eq 0 ]; then
    LOG "No user-установлен packages found"
    ALERT "No user-установлен packages to backup"
    rm -f "$temp_file"
    exit 0
fi

mv "$temp_file" "$BACKUP_FILE"

LOG "Packages backed up: $pkg_count"
LOG "Backup location: $BACKUP_FILE"

LOG "User-установлен packages:"
while IFS= read -r pkg; do
    LOG "  • $pkg"
done < "$BACKUP_FILE"

ALERT "Backed up $pkg_count packages"
