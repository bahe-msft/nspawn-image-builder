#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse flags
VARIANT=""
ARCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --arch)    ARCH="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "${VARIANT}" && -f "${SCRIPT_DIR}/variants/${VARIANT}.conf" ]]; then
    source "${SCRIPT_DIR}/variants/${VARIANT}.conf"
else
    source "${SCRIPT_DIR}/config.env"
fi

IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"

# Normalize architecture
if [[ -n "${ARCH}" ]]; then
    case "${ARCH}" in
        amd64|x86_64)  ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)
            echo "ERROR: Unsupported architecture: ${ARCH}" >&2
            exit 1
            ;;
    esac
    # Append architecture to image name if not default
    if [[ "${ARCH}" != "amd64" ]]; then
        IMAGE_NAME="${IMAGE_NAME}-${ARCH}"
    fi
fi

TARBALL="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

PASSED=0
FAILED=0

check() {
    local name="$1"
    shift
    if "$@" &>/dev/null; then
        echo "  PASS: ${name}"
        ((PASSED++)) || true
    else
        echo "  FAIL: ${name}"
        ((FAILED++)) || true
    fi
}

TESTDIR=$(mktemp -d /tmp/nspawn-validate.XXXXXX)
cleanup() { rm -rf "${TESTDIR}"; }
trap cleanup EXIT

echo "=== Validating nspawn image: ${IMAGE_NAME} ==="
echo

# 1. Tarball exists
echo "[1] Tarball existence"
check "Tarball exists" test -f "${TARBALL}"
check "Tarball non-empty" test -s "${TARBALL}"

# 2. Tarball extractable
echo "[2] Tarball extraction"
zstd -d < "${TARBALL}" | tar -C "${TESTDIR}" -xf - 2>/dev/null
check "Has /bin" test -d "${TESTDIR}/bin" -o -L "${TESTDIR}/bin"
check "Has /etc" test -d "${TESTDIR}/etc"
check "Has /usr" test -d "${TESTDIR}/usr"
check "Has /var" test -d "${TESTDIR}/var"

# 3. Basic rootfs structure
echo "[3] Rootfs structure"
check "Has /etc/os-release" test -f "${TESTDIR}/etc/os-release"
check "Has /bin/sh or /usr/bin/sh" test -f "${TESTDIR}/bin/sh" -o -f "${TESTDIR}/usr/bin/sh"

# 4. Custom packages installed
echo "[4] Extra packages"
for pkg in ${EXTRA_PACKAGES}; do
    check "Package: ${pkg}" chroot "${TESTDIR}" dpkg -s "${pkg}"
done

# 5. nspawn boot test
echo "[5] nspawn execution test"
OUTPUT=$(systemd-nspawn -D "${TESTDIR}" --pipe -- /bin/echo hello 2>/dev/null || true)
if [[ "${OUTPUT}" == *"hello"* ]]; then
    echo "  PASS: nspawn echo test"
    ((PASSED++)) || true
else
    echo "  FAIL: nspawn echo test (got: '${OUTPUT}')"
    ((FAILED++)) || true
fi

# 6. Customization marker
echo "[6] Customization marker"
check "Marker /etc/nspawn-customized exists" test -f "${TESTDIR}/etc/nspawn-customized"

# Summary
echo
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="
if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
exit 0
