#!/bin/bash
# Test suite: dev variant specifics

suite_header "Variant: dev"

# Customization marker
assert_file_exists "/etc/nspawn-customized"

# GCC works
if chroot_exec gcc --version &>/dev/null; then
    test_pass "gcc works"
else
    test_fail "gcc works"
fi

# Python3 works
if chroot_exec python3 --version &>/dev/null; then
    test_pass "python3 works"
else
    test_fail "python3 works"
fi

# Git works
if chroot_exec git --version &>/dev/null; then
    test_pass "git works"
else
    test_fail "git works"
fi

# Make works
if chroot_exec make --version &>/dev/null; then
    test_pass "make works"
else
    test_fail "make works"
fi

# Dev profile exists
assert_file_exists "/etc/profile.d/dev.sh"

# Git default branch is main
DEFAULT_BRANCH=$(chroot_exec git config --system init.defaultBranch 2>/dev/null || true)
if [[ "${DEFAULT_BRANCH}" == "main" ]]; then
    test_pass "git default branch is main"
else
    test_fail "git default branch is main" "got: '${DEFAULT_BRANCH}'"
fi

# /workspace directory exists
assert_dir_exists "/workspace"
