#!/bin/sh
set -euo pipefail

LOG="/var/log/messages"
DATE="$(date +%F)"
TARGET="logs-$DATE"
MOUNT_USB="/mnt/syslog-usb"
MOUNT_SD="/mnt/syslog-sd"
OFFFILE_SUBDIR="syslog-backups/.syslog-sync.offset"
LOCKFILE="/run/syslog-sync.lock"
MIN_FREE_KB=1024        # 1 MB
BATCH_DELETE_KB=5120    # ~5 MB

log(){ echo "$(date '+%F %T') [syslog-sync] $*"; }

# 0) Ensure runtime dirs & lock-file exist
mkdir -p "$MOUNT_USB" "$MOUNT_SD"
mkdir -p "$(dirname "$LOCKFILE")"
: > "$LOCKFILE"

# 1) Prevent overlapping runs
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# 2) Detect device
if [ -b "/dev/sda1" ]; then
    DEV="/dev/sda1"; MNT="$MOUNT_USB"
elif [ -b "/dev/mmcblk1p1" ]; then
    DEV="/dev/mmcblk1p1"; MNT="$MOUNT_SD"
else
    log "No USB or SD detected"
    exit 1
fi

# 3) Mount if not already
if ! mountpoint -q "$MNT"; then
    log "Mounting $DEV on $MNT"
    mount -o noatime,nodiratime "$DEV" "$MNT"
fi

# 4) Prune oldest logs if < MIN_FREE_KB
AVAIL_KB=$(df -k "$MNT" | awk 'NR==2{print $4}')
if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
    TO_DEL=""
    SUM=0
    for F in $(ls -1tr "$MNT/syslog-backups" 2>/dev/null | grep '^logs-'); do
        FILE_PATH="$MNT/syslog-backups/$F"
        SZ=$(du -k "$FILE_PATH" | awk '{print $1}')
        SUM=$((SUM+SZ))
        TO_DEL="$TO_DEL $FILE_PATH"
        [ "$SUM" -ge "$BATCH_DELETE_KB" ] && break
    done

    if [ -z "$TO_DEL" ]; then
        log "Low space & no logs to delete; skipping"
        umount "$MNT"; exit 1
    fi

    log "Deleting ~${BATCH_DELETE_KB}kB: $TO_DEL"
    for FP in $TO_DEL; do
        rm -f "$FP" || true
    done

    # re-check free space
    AVAIL_KB=$(df -k "$MNT" | awk 'NR==2{print $4}')
    if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
        log "Still low space after deletion; skipping"
        umount "$MNT"; exit 1
    fi
fi

# 5) Append-only backup
mkdir -p "$MNT/syslog-backups"
OFF="$MNT/$OFFFILE_SUBDIR"
LAST=0; [ -f "$OFF" ] && LAST=$(cat "$OFF")
CUR=$(wc -c "$LOG" | awk '{print $1}')

if [ "$CUR" -lt "$LAST" ]; then
    log "Log truncated; appending entire file"
    cat "$LOG" >> "$MNT/syslog-backups/$TARGET"
elif [ "$CUR" -gt "$LAST" ]; then
    log "Appending bytes $((LAST+1))–$CUR"
    tail -c +"$((LAST+1))" "$LOG" >> "$MNT/syslog-backups/$TARGET"
else
    log "No new data; skipping"
fi
echo "$CUR" > "$OFF"

# 6) Flush and unmount
sync
umount "$MNT"
