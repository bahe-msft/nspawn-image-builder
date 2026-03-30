#!/bin/bash
# Test suite: basic security checks

suite_header "Security"

# No world-writable files outside /tmp and /var/tmp
WORLD_WRITABLE=$(find "${ROOTFS}" -xdev -path "${ROOTFS}/tmp" -prune -o -path "${ROOTFS}/var/tmp" -prune -o -path "${ROOTFS}/proc" -prune -o -path "${ROOTFS}/sys" -prune -o -path "${ROOTFS}/dev" -prune -o -type f -perm -0002 -print 2>/dev/null | head -5)
if [[ -z "${WORLD_WRITABLE}" ]]; then
    test_pass "no world-writable files outside /tmp"
else
    test_fail "no world-writable files outside /tmp" "found: $(echo "${WORLD_WRITABLE}" | head -3)"
fi

# No unexpected SUID binaries
SUID_BINS=$(find "${ROOTFS}" -xdev -path "${ROOTFS}/proc" -prune -o -path "${ROOTFS}/sys" -prune -o -path "${ROOTFS}/dev" -prune -o -type f -perm -4000 -print 2>/dev/null || true)
# Common expected SUID: su, sudo, passwd, chsh, chfn, newgrp, mount, umount, ping
UNEXPECTED_SUID=""
for f in ${SUID_BINS}; do
    base=$(basename "$f")
    case "${base}" in
        su|sudo|passwd|chsh|chfn|newgrp|mount|umount|ping|gpasswd) ;;
        *) UNEXPECTED_SUID+="${f} " ;;
    esac
done
if [[ -z "${UNEXPECTED_SUID}" ]]; then
    test_pass "no unexpected SUID binaries"
else
    test_fail "no unexpected SUID binaries" "found: ${UNEXPECTED_SUID}"
fi

# /etc/shadow exists with restrictive permissions
if [[ -f "${ROOTFS}/etc/shadow" ]]; then
    SHADOW_PERM=$(stat -c '%a' "${ROOTFS}/etc/shadow")
    if [[ "${SHADOW_PERM}" == "640" || "${SHADOW_PERM}" == "600" ]]; then
        test_pass "/etc/shadow has restrictive permissions (${SHADOW_PERM})"
    else
        test_fail "/etc/shadow has restrictive permissions" "got ${SHADOW_PERM}"
    fi
else
    test_fail "/etc/shadow exists"
fi

# No empty password hashes (except root, which is intentionally passwordless)
EMPTY_PW=$(awk -F: '$2 == "" && $1 != "root" { print $1 }' "${ROOTFS}/etc/shadow" 2>/dev/null || true)
if [[ -z "${EMPTY_PW}" ]]; then
    test_pass "no non-root accounts with empty passwords"
else
    test_fail "no non-root accounts with empty passwords" "accounts: ${EMPTY_PW}"
fi

# /etc/passwd has correct permissions
assert_perm "/etc/passwd" "644"
