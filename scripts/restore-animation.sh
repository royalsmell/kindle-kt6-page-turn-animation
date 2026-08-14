#!/bin/sh
# Name: KT6 恢复动画修改（使用检查备份）
# Author: Codex
# DontUseFBInk

REPORT="/mnt/us/KT6-animation-restore-result.txt"
SOURCE="/etc/deviceConfig.conf"
BACKUP="/mnt/us/deviceConfig.conf.before-animation.encrypted.bak"
VERIFY="/tmp/deviceConfig.animation-restore-verify.$$"
STAGED="/etc/.deviceConfig.conf.animation-restore.$$"
ROOT_RW=0

write() { printf '%s\n' "$1" >> "$REPORT"; }
cleanup() {
    rm -f "$VERIFY"
    if [ "$ROOT_RW" = "1" ]; then
        rm -f "$STAGED"
        sync
        mntroot ro >/dev/null 2>&1
    fi
}
trap cleanup EXIT HUP INT TERM

: > "$REPORT" || exit 1
write "KT6 animation modification restore"
write "=================================="
write "Time: $(date 2>/dev/null)"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
    write "FAIL: This script is not running as root."
    exit 2
fi
if [ ! -r /proc/usid ] || [ "$(cut -c 1-6 /proc/usid 2>/dev/null)" != "G093KM" ]; then
    write "FAIL: Device prefix is not G093KM."
    exit 3
fi
if [ ! -s "$BACKUP" ] || ! command -v devcap-encrypt >/dev/null 2>&1; then
    write "FAIL: The checked encrypted backup or decrypt tool is unavailable."
    exit 4
fi

if ! devcap-encrypt -i "$BACKUP" "$VERIFY" >/dev/null 2>&1 || [ ! -s "$VERIFY" ]; then
    write "FAIL: Backup could not be decrypted."
    exit 5
fi

FALSE_COUNT="$(awk '
    /^\[ri7\][[:space:]]*$/ { inside=1; next }
    /^\[/ && inside { exit }
    inside && /^swipeMode\.available=false[[:space:]]*$/ { count++ }
    END { print count+0 }
' "$VERIFY" 2>/dev/null)"
if [ "$FALSE_COUNT" != "1" ]; then
    write "FAIL: Backup does not contain exactly one disabled [ri7] animation flag."
    exit 6
fi
write "Backup validation: PASS"

if ! mntroot rw >/dev/null 2>&1; then
    write "FAIL: Could not make rootfs writable."
    exit 7
fi
ROOT_RW=1

if ! cp -p "$SOURCE" "$STAGED" 2>/dev/null; then
    write "FAIL: Could not create restore staging file."
    exit 8
fi
if ! (umask 077; : > "$STAGED" && cat "$BACKUP" > "$STAGED"); then
    write "FAIL: Could not populate restore staging file."
    exit 9
fi
if ! cmp -s "$BACKUP" "$STAGED" || ! mv -f "$STAGED" "$SOURCE"; then
    write "FAIL: Restore installation verification failed."
    exit 10
fi
sync

rm -f "$VERIFY"
if ! devcap-encrypt -i "$SOURCE" "$VERIFY" >/dev/null 2>&1; then
    write "FAIL: Restored configuration could not be verified."
    exit 11
fi
FALSE_COUNT="$(awk '
    /^\[ri7\][[:space:]]*$/ { inside=1; next }
    /^\[/ && inside { exit }
    inside && /^swipeMode\.available=false[[:space:]]*$/ { count++ }
    END { print count+0 }
' "$VERIFY" 2>/dev/null)"
if [ "$FALSE_COUNT" != "1" ]; then
    write "FAIL: Restored animation flag verification failed."
    exit 12
fi

if ! mntroot ro >/dev/null 2>&1; then
    write "WARNING: Backup was restored, but rootfs could not be remounted read-only."
    write "Restart the Kindle now."
    ROOT_RW=0
    exit 13
fi
ROOT_RW=0

write "RESULT: SUCCESS - the checked pre-animation configuration was restored."
write "Restart the Kindle manually."
exit 0
