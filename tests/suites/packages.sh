#!/bin/bash
# Test suite: package verification

suite_header "Package Verification"

# Core packages must be installed
for pkg in systemd dbus; do
    if chroot_exec dpkg -s "${pkg}" &>/dev/null; then
        test_pass "core package installed: ${pkg}"
    else
        test_fail "core package installed: ${pkg}"
    fi
done

# All EXTRA_PACKAGES from variant config
for pkg in ${EXTRA_PACKAGES}; do
    if chroot_exec dpkg -s "${pkg}" &>/dev/null; then
        test_pass "extra package installed: ${pkg}"
    else
        test_fail "extra package installed: ${pkg}"
    fi
done

# No broken packages
AUDIT_OUTPUT=$(chroot_exec dpkg --audit 2>&1 || true)
if [[ -z "${AUDIT_OUTPUT}" ]]; then
    test_pass "dpkg audit clean (no broken packages)"
else
    test_fail "dpkg audit clean" "broken packages found"
fi

# Spot-check that key binaries are actually executable
for bin in /usr/bin/curl /usr/bin/wget /usr/bin/vim.tiny; do
    if [[ -x "${ROOTFS}/${bin}" ]]; then
        test_pass "binary executable: ${bin}"
    elif [[ -f "${ROOTFS}/${bin}" ]]; then
        test_fail "binary executable: ${bin}" "exists but not executable"
    else
        test_skip "binary executable: ${bin}" "not in this variant"
    fi
done
