#!/bin/bash
# Test suite: gpu variant specifics

suite_header "Variant: gpu"

# Customization marker
assert_file_exists "/etc/nspawn-customized"

# Verify this is Ubuntu Noble
if grep -qi "ubuntu" "${ROOTFS}/etc/os-release" 2>/dev/null; then
    test_pass "os-release identifies as Ubuntu"
else
    test_fail "os-release identifies as Ubuntu"
fi

if grep -q "noble" "${ROOTFS}/etc/os-release" 2>/dev/null; then
    test_pass "os-release contains noble"
else
    test_fail "os-release contains noble"
fi

# Hostname
if [[ -f "${ROOTFS}/etc/hostname" ]]; then
    HOSTNAME_VAL=$(cat "${ROOTFS}/etc/hostname")
    if [[ "${HOSTNAME_VAL}" == "nspawn-gpu" ]]; then
        test_pass "hostname is nspawn-gpu"
    else
        test_fail "hostname is nspawn-gpu" "got: ${HOSTNAME_VAL}"
    fi
else
    test_fail "hostname is set" "/etc/hostname missing"
fi

# NVIDIA repository is configured
if ls "${ROOTFS}/etc/apt/sources.list.d/"*nvidia* &>/dev/null; then
    test_pass "NVIDIA apt repository configured"
    if grep -q "developer.download.nvidia.com" "${ROOTFS}/etc/apt/sources.list.d/"*nvidia* 2>/dev/null; then
        test_pass "NVIDIA repo points to developer.download.nvidia.com"
    else
        test_fail "NVIDIA repo points to developer.download.nvidia.com"
    fi
else
    test_fail "NVIDIA apt repository configured"
fi

# NVIDIA GPG keyring exists
assert_file_exists "/usr/share/keyrings/nvidia-cuda-keyring.gpg"

# nvidia-utils package is installed
if chroot_exec dpkg -l nvidia-utils-560 2>/dev/null | grep -q '^ii'; then
    test_pass "nvidia-utils-560 is installed"
else
    test_fail "nvidia-utils-560 is installed"
fi

# nvidia-smi binary exists
if [[ -x "${ROOTFS}/usr/bin/nvidia-smi" ]]; then
    test_pass "nvidia-smi binary exists and is executable"
else
    test_fail "nvidia-smi binary exists and is executable"
fi

# libnvidia-compute is installed
if chroot_exec dpkg -l libnvidia-compute-560 2>/dev/null | grep -q '^ii'; then
    test_pass "libnvidia-compute-560 is installed"
else
    test_fail "libnvidia-compute-560 is installed"
fi
