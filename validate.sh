#!/usr/bin/env bash
#
# validate.sh — end-to-end validation for nspawn-image-builder artifacts
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load configuration ──────────────────────────────────────────────────────
IMAGE_NAME="nspawn-base"
EXTRA_PACKAGES=""
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# ── Root check ──────────────────────────────────────────────────────────────
if [[ $(id -u) -ne 0 ]]; then
    echo "ERROR: validate.sh must be run as root." >&2
    exit 1
fi

# ── State ───────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
TMP_DIR=""

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

# ── Helpers ─────────────────────────────────────────────────────────────────
pass() {
    echo "PASS: $1"
    (( PASSED++ )) || true
}

fail() {
    echo "FAIL: $1"
    (( FAILED++ )) || true
}

# ── Derived paths ───────────────────────────────────────────────────────────
TARBALL="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"

# ═════════════════════════════════════════════════════════════════════════════
# 1. Tarball exists
# ═════════════════════════════════════════════════════════════════════════════
if [[ -f "${TARBALL}" && -s "${TARBALL}" ]]; then
    pass "Tarball exists and is non-empty (${TARBALL})"
else
    fail "Tarball missing or empty (${TARBALL})"
    echo "Cannot continue without tarball. Aborting remaining checks." >&2
    echo ""
    echo "Summary: ${PASSED} passed, ${FAILED} failed."
    exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# 2. Tarball extractable + contains required top-level dirs
# ═════════════════════════════════════════════════════════════════════════════
TMP_DIR="$(mktemp -d /tmp/validate-nspawn.XXXXXXXXXX)"

if tar --zstd -xf "${TARBALL}" -C "${TMP_DIR}" 2>/dev/null; then
    EXTRACT_OK=true
else
    EXTRACT_OK=false
fi

if ${EXTRACT_OK}; then
    DIRS_OK=true
    for d in bin etc usr var; do
        if [[ ! -d "${TMP_DIR}/${d}" ]]; then
            DIRS_OK=false
            break
        fi
    done
    if ${DIRS_OK}; then
        pass "Tarball extractable with /bin, /etc, /usr, /var present"
    else
        fail "Tarball extracted but missing one or more of /bin, /etc, /usr, /var"
    fi
else
    fail "Tarball is not extractable"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 3. Basic rootfs structure
# ═════════════════════════════════════════════════════════════════════════════
if ${EXTRACT_OK}; then
    ROOTFS_OK=true

    if [[ ! -f "${TMP_DIR}/etc/os-release" ]]; then
        ROOTFS_OK=false
    fi
    # /bin/sh may be a symlink; -e follows symlinks inside the tree
    if [[ ! -e "${TMP_DIR}/bin/sh" ]]; then
        ROOTFS_OK=false
    fi

    if ${ROOTFS_OK}; then
        pass "Basic rootfs structure (/etc/os-release, /bin/sh)"
    else
        fail "Basic rootfs structure — missing /etc/os-release or /bin/sh"
    fi
else
    fail "Basic rootfs structure (skipped — extraction failed)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 4. Custom packages installed
# ═════════════════════════════════════════════════════════════════════════════
if ${EXTRACT_OK} && [[ -n "${EXTRA_PACKAGES}" ]]; then
    PKG_ALL_OK=true
    for pkg in ${EXTRA_PACKAGES}; do
        if chroot "${TMP_DIR}" dpkg -s "${pkg}" >/dev/null 2>&1; then
            pass "Package '${pkg}' is installed"
        else
            fail "Package '${pkg}' is NOT installed"
            PKG_ALL_OK=false
        fi
    done
elif ${EXTRACT_OK}; then
    pass "Custom packages (none configured — nothing to check)"
else
    fail "Custom packages (skipped — extraction failed)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 5. nspawn boot test
# ═════════════════════════════════════════════════════════════════════════════
if ${EXTRACT_OK}; then
    NSPAWN_OUTPUT=""
    if NSPAWN_OUTPUT=$(systemd-nspawn -D "${TMP_DIR}" --pipe -- /bin/echo hello 2>/dev/null); then
        if [[ "${NSPAWN_OUTPUT}" == "hello" ]]; then
            pass "nspawn boot test — output matched 'hello'"
        else
            fail "nspawn boot test — unexpected output: '${NSPAWN_OUTPUT}'"
        fi
    else
        fail "nspawn boot test — systemd-nspawn exited with non-zero status"
    fi
else
    fail "nspawn boot test (skipped — extraction failed)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 6. Customize scripts ran (marker file)
# ═════════════════════════════════════════════════════════════════════════════
if ${EXTRACT_OK}; then
    if [[ -f "${TMP_DIR}/etc/nspawn-customized" ]]; then
        pass "Customize marker /etc/nspawn-customized exists"
    else
        fail "Customize marker /etc/nspawn-customized not found"
    fi
else
    fail "Customize marker (skipped — extraction failed)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "Summary: ${PASSED} passed, ${FAILED} failed."

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi

exit 0
