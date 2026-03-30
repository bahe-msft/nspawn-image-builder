#!/bin/bash
# Test helper library — TAP-format output with color
#
# Provides assertion functions for test suites.
# Sourced by run-tests.sh; do not execute directly.

# TAP counters
_TAP_COUNT=0
_TAP_PASS=0
_TAP_FAIL=0
_TAP_SKIP=0

# Color helpers (disable if not a tty)
if [[ -t 1 ]]; then
    _GREEN='\033[0;32m'
    _RED='\033[0;31m'
    _YELLOW='\033[0;33m'
    _CYAN='\033[0;36m'
    _BOLD='\033[1m'
    _RESET='\033[0m'
else
    _GREEN='' _RED='' _YELLOW='' _CYAN='' _BOLD='' _RESET=''
fi

test_pass() {
    ((_TAP_COUNT++)) || true
    ((_TAP_PASS++)) || true
    echo -e "${_GREEN}ok ${_TAP_COUNT}${_RESET} - $1"
}

test_fail() {
    ((_TAP_COUNT++)) || true
    ((_TAP_FAIL++)) || true
    echo -e "${_RED}not ok ${_TAP_COUNT}${_RESET} - $1"
    if [[ -n "${2:-}" ]]; then
        echo "  # $2"
    fi
}

test_skip() {
    ((_TAP_COUNT++)) || true
    ((_TAP_SKIP++)) || true
    echo -e "${_YELLOW}ok ${_TAP_COUNT}${_RESET} - $1 # SKIP ${2:-}"
}

# assert <description> <command...>
assert() {
    local desc="$1"; shift
    if "$@" &>/dev/null; then
        test_pass "${desc}"
    else
        test_fail "${desc}" "command: $*"
    fi
}

# assert_not <description> <command...> — passes when command fails
assert_not() {
    local desc="$1"; shift
    if ! "$@" &>/dev/null; then
        test_pass "${desc}"
    else
        test_fail "${desc}" "expected failure but got success: $*"
    fi
}

assert_file_exists() {
    assert "file exists: $1" test -f "${ROOTFS}/$1"
}

assert_dir_exists() {
    assert "dir exists: $1" test -d "${ROOTFS}/$1"
}

assert_executable() {
    local path="$1"
    if [[ -x "${ROOTFS}/${path}" ]]; then
        test_pass "executable: ${path}"
    elif [[ -L "${ROOTFS}/${path}" ]]; then
        # Follow symlink
        local target
        target=$(readlink -f "${ROOTFS}/${path}")
        if [[ -x "${target}" ]]; then
            test_pass "executable: ${path} (symlink)"
        else
            test_fail "executable: ${path}" "symlink target not executable: ${target}"
        fi
    else
        test_fail "executable: ${path}" "not found or not executable"
    fi
}

# assert_perm <path-relative-to-rootfs> <expected-octal>
assert_perm() {
    local path="${ROOTFS}/$1"
    local expected="$2"
    local actual
    actual=$(stat -c '%a' "${path}" 2>/dev/null || echo "MISSING")
    if [[ "${actual}" == "${expected}" ]]; then
        test_pass "permissions ${expected}: $1"
    else
        test_fail "permissions ${expected}: $1" "got ${actual}"
    fi
}

# chroot_exec <command...> — run a command inside the rootfs via chroot
chroot_exec() {
    chroot "${ROOTFS}" "$@" 2>/dev/null
}

# nspawn_exec <command...> — run via systemd-nspawn if available
nspawn_exec() {
    if command -v systemd-nspawn &>/dev/null; then
        systemd-nspawn -D "${ROOTFS}" --pipe -- "$@" 2>/dev/null
    else
        return 1
    fi
}

suite_header() {
    echo ""
    echo -e "${_CYAN}${_BOLD}# $1${_RESET}"
}

tap_summary() {
    echo ""
    echo -e "${_BOLD}1..${_TAP_COUNT}${_RESET}"
    echo -e "${_GREEN}# pass: ${_TAP_PASS}${_RESET}"
    if [[ ${_TAP_FAIL} -gt 0 ]]; then
        echo -e "${_RED}# fail: ${_TAP_FAIL}${_RESET}"
    fi
    if [[ ${_TAP_SKIP} -gt 0 ]]; then
        echo -e "${_YELLOW}# skip: ${_TAP_SKIP}${_RESET}"
    fi
    echo "# total: ${_TAP_COUNT}"
    return ${_TAP_FAIL}
}
