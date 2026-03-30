#!/bin/bash
# Test suite: rootfs structure validation

suite_header "Rootfs Structure"

# Required directories
for dir in /etc /usr /var /tmp /root; do
    assert_dir_exists "${dir}"
done

# /bin and /sbin may be symlinks on modern distros
if [[ -d "${ROOTFS}/bin" || -L "${ROOTFS}/bin" ]]; then
    test_pass "dir exists: /bin (or symlink)"
else
    test_fail "dir exists: /bin"
fi

if [[ -d "${ROOTFS}/sbin" || -L "${ROOTFS}/sbin" ]]; then
    test_pass "dir exists: /sbin (or symlink)"
else
    test_fail "dir exists: /sbin"
fi

if [[ -d "${ROOTFS}/lib" || -L "${ROOTFS}/lib" ]]; then
    test_pass "dir exists: /lib (or symlink)"
else
    test_fail "dir exists: /lib"
fi

# os-release
assert_file_exists "/etc/os-release"

# Check distro in os-release
if grep -qi "ubuntu" "${ROOTFS}/etc/os-release" 2>/dev/null; then
    test_pass "os-release contains Ubuntu"
else
    test_fail "os-release contains Ubuntu"
fi

# Shell exists and is executable
if [[ -x "${ROOTFS}/bin/sh" || -x "${ROOTFS}/usr/bin/sh" ]]; then
    test_pass "executable: /bin/sh or /usr/bin/sh"
else
    test_fail "executable: /bin/sh" "no working shell found"
fi

# /tmp should be clean (no leftover build artifacts)
TMP_COUNT=$(find "${ROOTFS}/tmp" -mindepth 1 2>/dev/null | wc -l)
if [[ ${TMP_COUNT} -eq 0 ]]; then
    test_pass "/tmp is clean"
else
    test_fail "/tmp is clean" "found ${TMP_COUNT} leftover files"
fi

# Apt cache should be clean
APT_CACHE_SIZE=$(du -s "${ROOTFS}/var/cache/apt/" 2>/dev/null | awk '{print $1}')
if [[ ${APT_CACHE_SIZE:-0} -lt 1024 ]]; then
    test_pass "apt cache is clean"
else
    test_fail "apt cache is clean" "${APT_CACHE_SIZE}K remaining"
fi

# Filesystem permissions
assert_perm "/" "755"
assert_perm "/tmp" "1777"
assert_perm "/etc" "755"
