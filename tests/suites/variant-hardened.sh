#!/bin/bash
# Test suite: hardened variant specifics

suite_header "Variant: hardened"

# Customization marker
assert_file_exists "/etc/nspawn-customized"

# Security tools installed
for pkg in ufw fail2ban auditd aide apparmor; do
    if chroot_exec dpkg -s "${pkg}" &>/dev/null; then
        test_pass "package installed: ${pkg}"
    else
        test_fail "package installed: ${pkg}"
    fi
done

# Sysctl hardening file exists
assert_file_exists "/etc/sysctl.d/99-hardening.conf"

# Check key sysctl values in the config
SYSCTL_FILE="${ROOTFS}/etc/sysctl.d/99-hardening.conf"
for setting in "net.ipv4.ip_forward = 0" "net.ipv4.tcp_syncookies = 1" "kernel.randomize_va_space = 2" "kernel.dmesg_restrict = 1"; do
    key=$(echo "${setting}" | cut -d= -f1 | xargs)
    if grep -q "${key}" "${SYSCTL_FILE}" 2>/dev/null; then
        test_pass "sysctl: ${key}"
    else
        test_fail "sysctl: ${key}" "not found in hardening.conf"
    fi
done

# Fail2ban SSH jail configured
if [[ -f "${ROOTFS}/etc/fail2ban/jail.d/sshd.conf" ]]; then
    test_pass "fail2ban SSH jail configured"
    if grep -q 'enabled = true' "${ROOTFS}/etc/fail2ban/jail.d/sshd.conf"; then
        test_pass "fail2ban SSH jail enabled"
    else
        test_fail "fail2ban SSH jail enabled"
    fi
else
    test_fail "fail2ban SSH jail configured"
    test_fail "fail2ban SSH jail enabled" "jail file missing"
fi

# Auditd rules exist
assert_file_exists "/etc/audit/rules.d/hardening.rules"

# SSH hardening (if sshd_config exists)
if [[ -f "${ROOTFS}/etc/ssh/sshd_config" ]]; then
    if grep -q '^PermitRootLogin no' "${ROOTFS}/etc/ssh/sshd_config"; then
        test_pass "SSH: root login disabled"
    else
        test_fail "SSH: root login disabled"
    fi
    if grep -q '^PasswordAuthentication no' "${ROOTFS}/etc/ssh/sshd_config"; then
        test_pass "SSH: password auth disabled"
    else
        test_fail "SSH: password auth disabled"
    fi
else
    test_skip "SSH: root login disabled" "sshd_config not present"
    test_skip "SSH: password auth disabled" "sshd_config not present"
fi

# Automatic security updates configured
assert_file_exists "/etc/apt/apt.conf.d/50unattended-upgrades"
assert_file_exists "/etc/apt/apt.conf.d/20auto-upgrades"
