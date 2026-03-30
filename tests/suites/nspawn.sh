#!/bin/bash
# Test suite: systemd-nspawn runtime tests

suite_header "nspawn Runtime"

if ! command -v systemd-nspawn &>/dev/null; then
    test_skip "nspawn tests" "systemd-nspawn not available"
else
    # Unmount before nspawn (it does its own mounting)
    umount -lf "${ROOTFS}/proc" 2>/dev/null || true
    umount -lf "${ROOTFS}/sys" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev" 2>/dev/null || true

    # Basic command execution
    OUTPUT=$(nspawn_exec /bin/echo hello 2>/dev/null || true)
    if [[ "${OUTPUT}" == *"hello"* ]]; then
        test_pass "nspawn: echo command"
    else
        test_fail "nspawn: echo command" "got: '${OUTPUT}'"
    fi

    # /proc is mounted
    OUTPUT=$(nspawn_exec /bin/cat /proc/version 2>/dev/null || true)
    if [[ "${OUTPUT}" == *"Linux"* ]]; then
        test_pass "nspawn: /proc is mounted"
    else
        test_fail "nspawn: /proc is mounted"
    fi

    # /sys is accessible
    OUTPUT=$(nspawn_exec /bin/ls /sys/kernel 2>/dev/null || true)
    if [[ -n "${OUTPUT}" ]]; then
        test_pass "nspawn: /sys is accessible"
    else
        test_fail "nspawn: /sys is accessible"
    fi

    # Can read its own os-release
    OUTPUT=$(nspawn_exec /bin/cat /etc/os-release 2>/dev/null || true)
    if echo "${OUTPUT}" | grep -qiE 'ubuntu|debian'; then
        test_pass "nspawn: read /etc/os-release"
    else
        test_fail "nspawn: read /etc/os-release"
    fi

    # DNS resolution (best-effort; skip if no network)
    OUTPUT=$(nspawn_exec /usr/bin/getent hosts ubuntu.com 2>/dev/null || true)
    if [[ -n "${OUTPUT}" ]]; then
        test_pass "nspawn: DNS resolution"
    else
        test_skip "nspawn: DNS resolution" "no network or DNS unavailable"
    fi

    # Re-mount for any subsequent chroot-based suites
    mount --bind /dev "${ROOTFS}/dev" 2>/dev/null || true
    mount --bind /dev/pts "${ROOTFS}/dev/pts" 2>/dev/null || true
    mount -t proc proc "${ROOTFS}/proc" 2>/dev/null || true
    mount -t sysfs sys "${ROOTFS}/sys" 2>/dev/null || true
fi
