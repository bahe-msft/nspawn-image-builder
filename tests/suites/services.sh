#!/bin/bash
# Test suite: systemd service checks

suite_header "Systemd Services"

# Check enabled services
for svc in systemd-networkd systemd-resolved; do
    # Check if the symlink exists in the wants directory
    if [[ -L "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${svc}.service" ]] || \
       [[ -L "${ROOTFS}/etc/systemd/system/dbus-org.freedesktop.resolve1.service" && "${svc}" == "systemd-resolved" ]] || \
       chroot_exec systemctl is-enabled "${svc}" 2>/dev/null | grep -q 'enabled'; then
        test_pass "service enabled: ${svc}"
    else
        test_fail "service enabled: ${svc}"
    fi
done

# No obviously broken unit files
BAD_UNITS=$(chroot_exec systemctl list-unit-files --state=bad 2>/dev/null | grep -c 'bad' || true)
if [[ ${BAD_UNITS} -eq 0 ]]; then
    test_pass "no broken unit files"
else
    test_fail "no broken unit files" "${BAD_UNITS} bad unit(s)"
fi

# systemctl can list unit files (basic introspection works)
if chroot_exec systemctl list-unit-files --no-pager &>/dev/null; then
    test_pass "systemctl introspection works"
else
    test_fail "systemctl introspection works"
fi
