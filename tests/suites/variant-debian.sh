#!/bin/bash
# Test suite: debian variant specifics

suite_header "Variant: debian"

# Customization marker
assert_file_exists "/etc/nspawn-customized"

# Verify this is actually Debian (not Ubuntu)
if grep -qi "debian" "${ROOTFS}/etc/os-release" 2>/dev/null; then
    test_pass "os-release identifies as Debian"
else
    test_fail "os-release identifies as Debian"
fi

# Check Bookworm version
if grep -q "bookworm" "${ROOTFS}/etc/os-release" 2>/dev/null; then
    test_pass "os-release contains bookworm"
else
    test_fail "os-release contains bookworm"
fi

# Hostname was set
if [[ -f "${ROOTFS}/etc/hostname" ]]; then
    HOSTNAME_VAL=$(cat "${ROOTFS}/etc/hostname")
    if [[ "${HOSTNAME_VAL}" == "nspawn-debian" ]]; then
        test_pass "hostname is nspawn-debian"
    else
        test_fail "hostname is nspawn-debian" "got: ${HOSTNAME_VAL}"
    fi
else
    test_fail "hostname is set" "/etc/hostname missing"
fi

# Timezone is UTC
if [[ -L "${ROOTFS}/etc/localtime" ]]; then
    TZ_TARGET=$(readlink -f "${ROOTFS}/etc/localtime")
    if [[ "${TZ_TARGET}" == *"UTC"* ]]; then
        test_pass "timezone is UTC"
    else
        test_fail "timezone is UTC" "points to ${TZ_TARGET}"
    fi
else
    test_skip "timezone is UTC" "/etc/localtime is not a symlink"
fi

# Debian apt sources configured
if [[ -f "${ROOTFS}/etc/apt/sources.list.d/debian.sources" ]]; then
    test_pass "debian.sources file exists"
    if grep -q "deb.debian.org" "${ROOTFS}/etc/apt/sources.list.d/debian.sources" 2>/dev/null; then
        test_pass "debian.sources uses deb.debian.org"
    else
        test_fail "debian.sources uses deb.debian.org"
    fi
else
    test_fail "debian.sources file exists"
fi
