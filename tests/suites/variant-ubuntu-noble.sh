#!/bin/bash
# Test suite: ubuntu-noble variant specifics

suite_header "Variant: ubuntu-noble"

# Customization marker
assert_file_exists "/etc/nspawn-customized"

# Hostname was set
if [[ -f "${ROOTFS}/etc/hostname" ]]; then
    HOSTNAME_VAL=$(cat "${ROOTFS}/etc/hostname")
    if [[ -n "${HOSTNAME_VAL}" ]]; then
        test_pass "hostname is set (${HOSTNAME_VAL})"
    else
        test_fail "hostname is set" "file exists but empty"
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
