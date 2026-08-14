#!/bin/sh
# Name: KT6 动画兼容性检查（只读）
# Author: Codex
# DontUseFBInk

# This script is intentionally read-only with respect to Kindle rootfs.
# It never calls "mntroot rw" and never replaces /etc/deviceConfig.conf.

REPORT="/mnt/us/KT6-animation-check.txt"
BACKUP="/mnt/us/deviceConfig.conf.before-animation.encrypted.bak"
SOURCE="/etc/deviceConfig.conf"
TEMP="/tmp/deviceConfig.animation-check.$$"

cleanup() {
    rm -f "$TEMP"
}
trap cleanup EXIT HUP INT TERM

write() {
    printf '%s\n' "$1" >> "$REPORT"
}

: > "$REPORT" || exit 1
write "KT6 reading-animation compatibility check"
write "========================================"
write "Time: $(date 2>/dev/null)"
write "Mode: READ ONLY - no system configuration will be changed"
write ""

if [ -r /proc/usid ]; then
    SERIAL_PREFIX="$(cut -c 1-6 /proc/usid 2>/dev/null)"
    write "Serial prefix: $SERIAL_PREFIX"
    if [ "$SERIAL_PREFIX" = "G093KM" ]; then
        write "Model check: PASS (G093KM / Kindle Basic 2024 family)"
    else
        write "Model check: WARNING (expected G093KM, found $SERIAL_PREFIX)"
    fi
else
    write "Serial prefix: unavailable"
    write "Model check: WARNING (could not read /proc/usid)"
fi

if [ -r /etc/version.txt ]; then
    VERSION_LINE="$(grep -m 1 -E 'Kindle|System|Version|5\.' /etc/version.txt 2>/dev/null)"
    [ -n "$VERSION_LINE" ] || VERSION_LINE="$(head -n 1 /etc/version.txt 2>/dev/null)"
    write "Firmware info: $VERSION_LINE"
elif [ -r /etc/prettyversion.txt ]; then
    write "Firmware info: $(head -n 1 /etc/prettyversion.txt 2>/dev/null)"
else
    write "Firmware info: unavailable"
fi

write ""

if [ ! -r "$SOURCE" ]; then
    write "Config check: FAIL - $SOURCE is not readable"
    write "RESULT: STOP. Do not run the animation enabler."
    exit 2
fi

if ! command -v devcap-encrypt >/dev/null 2>&1; then
    write "Decrypt tool: FAIL - devcap-encrypt was not found"
    write "RESULT: STOP. Do not run the animation enabler."
    exit 3
fi
write "Decrypt tool: PASS"

# Keep a byte-for-byte encrypted backup on user-visible storage.
if cp "$SOURCE" "$BACKUP" 2>/dev/null && cmp -s "$SOURCE" "$BACKUP"; then
    write "Encrypted backup: PASS"
    write "Backup path: $BACKUP"
else
    rm -f "$BACKUP"
    write "Encrypted backup: FAIL"
    write "RESULT: STOP. Do not run the animation enabler."
    exit 4
fi

if ! devcap-encrypt -i "$SOURCE" "$TEMP" >/dev/null 2>&1; then
    write "Decrypt test: FAIL"
    write "RESULT: STOP. Do not run the animation enabler."
    exit 5
fi

if [ ! -s "$TEMP" ]; then
    write "Decrypt test: FAIL - decrypted output is empty"
    write "RESULT: STOP. Do not run the animation enabler."
    exit 6
fi
write "Decrypt test: PASS"

# Inspect only the [ri7] section and do not export the complete plaintext file.
RI7_BLOCK="$(awk '
    /^\[ri7\][[:space:]]*$/ { inside=1; found=1; next }
    /^\[/ && inside { exit }
    inside { print }
    END { if (!found) exit 7 }
' "$TEMP" 2>/dev/null)"
AWK_STATUS=$?

if [ "$AWK_STATUS" -ne 0 ]; then
    write "[ri7] section: FAIL - section not found"
    write "RESULT: STOP. This configuration does not match the supplied tool."
    exit 7
fi
write "[ri7] section: PASS"

FALSE_COUNT="$(printf '%s\n' "$RI7_BLOCK" | grep -c '^swipeMode\.available=false[[:space:]]*$')"
TRUE_COUNT="$(printf '%s\n' "$RI7_BLOCK" | grep -c '^swipeMode\.available=true[[:space:]]*$')"

if [ "$FALSE_COUNT" = "1" ] && [ "$TRUE_COUNT" = "0" ]; then
    write "Animation flag: swipeMode.available=false"
    write "Flag check: PASS - exactly one disabled flag was found"
    write "RESULT: COMPATIBLE. Send this report back before enabling."
    exit 0
fi

if [ "$FALSE_COUNT" = "0" ] && [ "$TRUE_COUNT" = "1" ]; then
    write "Animation flag: swipeMode.available=true"
    write "Flag check: ALREADY ENABLED"
    write "RESULT: No change is necessary."
    exit 0
fi

write "Animation flag counts: false=$FALSE_COUNT, true=$TRUE_COUNT"
write "Flag check: FAIL - expected exactly one known flag"
write "RESULT: STOP. Do not run the animation enabler."
exit 8
