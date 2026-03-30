#!/bin/bash
# Test suite: systemd service checks

suite_header "Systemd Services"

# Check enabled services
# systemd-networkd and systemd-resolved may have symlinks in different locations
# depending on the distro version. Check multiple possible paths.
check_service_enabled() {
    local svc="$1"
    # Direct symlink in multi-user or network-online targets
    if find "${ROOTFS}/etc/systemd/system" -name "${svc}.service" -type l 2>/dev/null | grep -q .; then
        return 0
    fi
    # Alias symlinks (e.g., dbus-org.freedesktop.resolve1.service for systemd-resolved)
    if find "${ROOTFS}/etc/systemd/system" -lname "*${svc}*" 2>/dev/null | grep -q .; then
        return 0
    fi
    # Preset or static enablement via systemctl in chroot
    local state
    state=$(chroot_exec systemctl is-enabled "${svc}" 2>/dev/null || true)
    case "${state}" in
        enabled|enabled-runtime|static|indirect) return 0 ;;
    esac
    return 1
}

for svc in systemd-networkd systemd-resolved; do
    if check_service_enabled "${svc}"; then
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
