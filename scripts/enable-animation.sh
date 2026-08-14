#!/bin/sh
# Name: KT6 启用原生翻页动画（安全校验版）
# Author: Codex
# DontUseFBInk

REPORT="/mnt/us/KT6-animation-enable-result.txt"
SOURCE="/etc/deviceConfig.conf"
USB_BACKUP="/mnt/us/deviceConfig.conf.before-animation.encrypted.bak"
PLAIN_OLD="/tmp/deviceConfig.animation-old.$$"
PLAIN_NEW="/tmp/deviceConfig.animation-new.$$"
ENC_NEW="/tmp/deviceConfig.animation-new-encrypted.$$"
PLAIN_VERIFY="/tmp/deviceConfig.animation-verify.$$"
STAGED="/etc/.deviceConfig.conf.animation-new.$$"
ROOT_RW=0

write() {
    printf '%s\n' "$1" >> "$REPORT"
}

cleanup() {
    rm -f "$PLAIN_OLD" "$PLAIN_NEW" "$ENC_NEW" "$PLAIN_VERIFY"
    if [ "$ROOT_RW" = "1" ]; then
        rm -f "$STAGED"
        sync
        mntroot ro >/dev/null 2>&1
    fi
}
trap cleanup EXIT HUP INT TERM

: > "$REPORT" || exit 1
write "KT6 native reading-animation enabler"
write "===================================="
write "Time: $(date 2>/dev/null)"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
    write "FAIL: This script is not running as root."
    exit 2
fi

if [ ! -r /proc/usid ] || [ "$(cut -c 1-6 /proc/usid 2>/dev/null)" != "G093KM" ]; then
    write "FAIL: Device prefix is not G093KM. No change was made."
    exit 3
fi
write "Model check: PASS (G093KM)"

if [ ! -r /etc/version.txt ] || ! grep -q 'juno_1806' /etc/version.txt 2>/dev/null; then
    write "FAIL: Expected KT6 firmware family juno_1806 was not detected."
    write "No change was made."
    exit 4
fi
write "Firmware check: PASS (juno_1806 / 5.18.6)"

if [ ! -r "$SOURCE" ] || ! command -v devcap-encrypt >/dev/null 2>&1; then
    write "FAIL: Required system configuration or decrypt tool is unavailable."
    exit 5
fi

# Refuse to proceed without the externally stored, byte-identical backup
# created by the read-only checker.
if [ ! -s "$USB_BACKUP" ] || ! cmp -s "$SOURCE" "$USB_BACKUP"; then
    write "FAIL: The checked USB backup is missing or no longer matches the current config."
    write "Run the read-only compatibility checker again before enabling."
    exit 6
fi
write "External backup check: PASS"

if ! devcap-encrypt -i "$SOURCE" "$PLAIN_OLD" >/dev/null 2>&1 || [ ! -s "$PLAIN_OLD" ]; then
    write "FAIL: Current configuration could not be decrypted."
    exit 7
fi

# Replace exactly one known line, and only while inside the [ri7] section.
if ! awk '
    BEGIN { inside=0; changed=0 }
    /^\[ri7\][[:space:]]*$/ { inside=1; print; next }
    /^\[/ { inside=0 }
    inside && /^swipeMode\.available=false[[:space:]]*$/ {
        print "swipeMode.available=true"
        changed++
        next
    }
    { print }
    END { if (changed != 1) exit 9 }
' "$PLAIN_OLD" > "$PLAIN_NEW"; then
    write "FAIL: Expected exactly one disabled flag inside [ri7]."
    exit 8
fi

if [ ! -s "$PLAIN_NEW" ]; then
    write "FAIL: Modified plaintext validation failed."
    exit 9
fi

OLD_LINES="$(wc -l < "$PLAIN_OLD" 2>/dev/null)"
NEW_LINES="$(wc -l < "$PLAIN_NEW" 2>/dev/null)"
if [ "$OLD_LINES" != "$NEW_LINES" ]; then
    write "FAIL: Unexpected configuration line-count change."
    exit 10
fi

if ! devcap-encrypt -i "$PLAIN_NEW" "$ENC_NEW" >/dev/null 2>&1 || [ ! -s "$ENC_NEW" ]; then
    write "FAIL: Modified configuration could not be encrypted."
    exit 11
fi

# Before touching /etc, decrypt the newly encrypted file and compare it
# byte-for-byte with the intended plaintext.
if ! devcap-encrypt -i "$ENC_NEW" "$PLAIN_VERIFY" >/dev/null 2>&1; then
    write "FAIL: Encrypted output could not be read back."
    exit 12
fi
if ! cmp -s "$PLAIN_NEW" "$PLAIN_VERIFY"; then
    write "FAIL: Encryption round-trip verification did not match."
    exit 13
fi
write "Pre-write encryption verification: PASS"

# Rootfs is made writable only after every validation above has passed.
if ! mntroot rw >/dev/null 2>&1; then
    write "FAIL: Could not make rootfs writable."
    exit 14
fi
ROOT_RW=1

# Preserve the original file metadata in a same-filesystem staging file,
# replace its contents, verify it, then rename it atomically.
if ! cp -p "$SOURCE" "$STAGED" 2>/dev/null; then
    write "FAIL: Could not create the staged configuration."
    exit 15
fi
if ! (umask 077; : > "$STAGED" && cat "$ENC_NEW" > "$STAGED"); then
    write "FAIL: Could not populate the staged configuration."
    exit 16
fi
if ! cmp -s "$ENC_NEW" "$STAGED"; then
    write "FAIL: Staged configuration verification failed."
    exit 17
fi
if ! mv -f "$STAGED" "$SOURCE"; then
    write "FAIL: Could not install the staged configuration."
    exit 18
fi
sync

# Validate the installed file while rootfs is still available.
rm -f "$PLAIN_VERIFY"
if ! devcap-encrypt -i "$SOURCE" "$PLAIN_VERIFY" >/dev/null 2>&1 || ! cmp -s "$PLAIN_NEW" "$PLAIN_VERIFY"; then
    write "FAIL: Post-write verification failed. Starting automatic rollback."
    rm -f "$STAGED"
    if cp -p "$SOURCE" "$STAGED" 2>/dev/null && \
       (umask 077; : > "$STAGED" && cat "$USB_BACKUP" > "$STAGED") && \
       cmp -s "$USB_BACKUP" "$STAGED" && \
       mv -f "$STAGED" "$SOURCE"; then
        sync
        rm -f "$PLAIN_VERIFY"
        if devcap-encrypt -i "$SOURCE" "$PLAIN_VERIFY" >/dev/null 2>&1 && \
           grep -q '^swipeMode\.available=false[[:space:]]*$' "$PLAIN_VERIFY"; then
            write "Automatic rollback: PASS - the checked backup was restored."
            write "No animation change remains."
            exit 19
        fi
    fi
    write "Automatic rollback: FAIL. Do not restart; run the supplied restore script immediately."
    exit 21
fi

if ! mntroot ro >/dev/null 2>&1; then
    write "WARNING: Animation was enabled, but rootfs could not be remounted read-only."
    write "Restart the Kindle now."
    ROOT_RW=0
    exit 20
fi
ROOT_RW=0

write "Post-write verification: PASS"
write "RESULT: SUCCESS - swipeMode.available=true is installed for [ri7]."
write "Restart the Kindle manually, then open a text book and enable the option under Aa > More."
exit 0
