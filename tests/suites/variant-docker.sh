#!/bin/bash
# Test suite: docker variant specifics

suite_header "Variant: docker"

# Customization marker
assert_file_exists "/etc/nspawn-customized"

# Docker binary exists
if [[ -x "${ROOTFS}/usr/bin/docker" ]]; then
    test_pass "docker binary exists"
else
    test_fail "docker binary exists"
fi

# docker.service unit file exists
if [[ -f "${ROOTFS}/lib/systemd/system/docker.service" ]] || \
   [[ -f "${ROOTFS}/usr/lib/systemd/system/docker.service" ]]; then
    test_pass "docker.service unit exists"
else
    test_fail "docker.service unit exists"
fi

# containerd.service unit file exists
if [[ -f "${ROOTFS}/lib/systemd/system/containerd.service" ]] || \
   [[ -f "${ROOTFS}/usr/lib/systemd/system/containerd.service" ]]; then
    test_pass "containerd.service unit exists"
else
    test_fail "containerd.service unit exists"
fi

# Docker daemon.json exists with expected config
if [[ -f "${ROOTFS}/etc/docker/daemon.json" ]]; then
    test_pass "daemon.json exists"
    if grep -q 'overlay2' "${ROOTFS}/etc/docker/daemon.json"; then
        test_pass "daemon.json: overlay2 storage driver"
    else
        test_fail "daemon.json: overlay2 storage driver"
    fi
    if grep -q 'max-size' "${ROOTFS}/etc/docker/daemon.json"; then
        test_pass "daemon.json: log rotation configured"
    else
        test_fail "daemon.json: log rotation configured"
    fi
else
    test_fail "daemon.json exists"
    test_fail "daemon.json: overlay2 storage driver" "daemon.json missing"
    test_fail "daemon.json: log rotation configured" "daemon.json missing"
fi

# Docker compose plugin
if [[ -f "${ROOTFS}/usr/libexec/docker/cli-plugins/docker-compose" ]] || \
   chroot_exec docker compose version &>/dev/null; then
    test_pass "docker compose plugin installed"
else
    test_fail "docker compose plugin installed"
fi

# Docker group exists
if grep -q '^docker:' "${ROOTFS}/etc/group" 2>/dev/null; then
    test_pass "docker group exists"
else
    test_fail "docker group exists"
fi
