#!/bin/sh
set -euo pipefail

# ------------------------------
# CONFIG
# ------------------------------
SYSLOG="/var/log/messages"

# Application log control (ONE file only)
APP_LOG="/var/log/application_log"
APP_MAX_BYTES=$((5 * 1024))     # Max 5 KB
MAX_LINES=100                   # Keep last 100 lines

DATE="$(date +%F)"
TARGET="logs-$DATE"

MOUNT_USB="/mnt/syslog-usb"
MOUNT_SD="/mnt/syslog-sd"

LOCKFILE="/run/syslog-sync.lock"
MIN_FREE_KB=1024                # 1 MB minimum free
BATCH_DELETE_KB=5120            # delete ~5 MB when pruning

log(){ echo "$(date '+%F %T') [syslog-sync] $*"; }

# ------------------------------
# 0) Ensure runtime dirs exist
# ------------------------------
mkdir -p "$MOUNT_USB" "$MOUNT_SD"
mkdir -p "$(dirname "$LOCKFILE")"
: > "$LOCKFILE"

# ------------------------------
# 1) Prevent overlapping runs
# ------------------------------
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# ------------------------------
# 2) APPLICATION LOG TRIM (Create if missing + 5KB limit + last 100 lines)
# ------------------------------
# Create file if missing
if [ ! -f "$APP_LOG" ]; then
    touch "$APP_LOG"
    chmod 644 "$APP_LOG"
fi

APP_SIZE=$(stat -c%s "$APP_LOG" 2>/dev/null || echo 0)

if [ "$APP_SIZE" -gt "$APP_MAX_BYTES" ]; then
    log "application_log >5KB → trimming to last ${MAX_LINES} lines"

    # 1) Copy last lines to temp
    tail -n "$MAX_LINES" "$APP_LOG" > "${APP_LOG}.tmp"

    # 2) Truncate the existing file (inode preserved!)
    : > "$APP_LOG"

    # 3) Restore content to SAME file
    cat "${APP_LOG}.tmp" > "$APP_LOG"

    # 4) Remove temp file
    rm -f "${APP_LOG}.tmp"
fi

# ------------------------------
# 3) Detect storage device (USB preferred, else SD)
# ------------------------------
if [ -b "/dev/sda1" ]; then
    DEV="/dev/sda1"; MNT="$MOUNT_USB"
elif [ -b "/dev/mmcblk1p1" ]; then
    DEV="/dev/mmcblk1p1"; MNT="$MOUNT_SD"
else
    log "No USB or SD detected"
    exit 1
fi

# ------------------------------
# 4) Mount filesystem (if not mounted)
# ------------------------------
if ! mountpoint -q "$MNT"; then
    log "Mounting $DEV on $MNT"
    mount -o noatime,nodiratime "$DEV" "$MNT"
fi

# ------------------------------
# 5) Base Folder Structure
# ------------------------------
BASE_DIR="$MNT/wings/logs/syslog"
mkdir -p "$BASE_DIR"

# ------------------------------
# 6) Free-space check & prune logs
# ------------------------------
AVAIL_KB=$(df -k "$MNT" | awk 'NR==2{print $4}')

if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
    TO_DEL=""
    SUM=0

    for F in $(ls -1tr "$BASE_DIR" 2>/dev/null | grep '^logs-'); do
        FILE_PATH="$BASE_DIR/$F"
        SZ=$(du -k "$FILE_PATH" | awk '{print $1}')
        SUM=$((SUM + SZ))
        TO_DEL="$TO_DEL $FILE_PATH"
        [ "$SUM" -ge "$BATCH_DELETE_KB" ] && break
    done

    if [ -z "$TO_DEL" ]; then
        log "Low space & no syslog files to delete; skipping sync"
        umount "$MNT"; exit 1
    fi

    log "Deleting ~$BATCH_DELETE_KB KB: $TO_DEL"
    for FP in $TO_DEL; do rm -f "$FP" || true; done

    AVAIL_KB=$(df -k "$MNT" | awk 'NR==2{print $4}')
    if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
        log "Still low space after cleanup — skipping sync"
        umount "$MNT"; exit 1
    fi
fi

# ------------------------------
# 7) Offset-based syslog sync
# ------------------------------
OFF="$BASE_DIR/.syslog-sync.offset"
LAST=0
[ -f "$OFF" ] && LAST=$(cat "$OFF" 2>/dev/null || echo 0)

CUR=$(wc -c "$SYSLOG" | awk '{print $1}')

if [ "$CUR" -lt "$LAST" ]; then
    log "Syslog truncated → copying entire file → $BASE_DIR/$TARGET"
    cat "$SYSLOG" >> "$BASE_DIR/$TARGET"

elif [ "$CUR" -gt "$LAST" ]; then
    log "Appending bytes $((LAST+1))–$CUR → $BASE_DIR/$TARGET"
    tail -c +"$((LAST+1))" "$SYSLOG" >> "$BASE_DIR/$TARGET"

else
    log "No new syslog data"
fi

echo "$CUR" > "$OFF"

# ------------------------------
# 8) Finalize
# ------------------------------
sync
echo 1 > /proc/sys/vm/drop_caches >/dev/null 2>&1
#umount "$MNT"
log "Completed syslog sync cycle"
