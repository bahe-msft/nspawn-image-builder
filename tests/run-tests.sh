#!/bin/bash
set -euo pipefail

# Test runner for nspawn images.
#
# Usage:
#   sudo ./tests/run-tests.sh [--variant <name>] [--suite <name>] [--list]
#
# Extracts the built image tarball and runs test suites against the rootfs.
# Requires root for chroot/nspawn operations.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
VARIANT=""
SUITE_FILTER=""
LIST_ONLY=false
ARCH=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --suite)   SUITE_FILTER="$2"; shift 2 ;;
        --arch)    ARCH="$2"; shift 2 ;;
        --list)    LIST_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--variant <name>] [--suite <name>] [--arch <arch>] [--list]"
            echo ""
            echo "Options:"
            echo "  --variant <name>  Test a specific variant (base, dev, debian)"
            echo "  --suite <name>    Run only a specific test suite"
            echo "  --arch <arch>     Target architecture (amd64, arm64)"
            echo "  --list            List available test suites and exit"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Load configuration
if [[ -n "${VARIANT}" && -f "${PROJECT_DIR}/variants/${VARIANT}.conf" ]]; then
    source "${PROJECT_DIR}/variants/${VARIANT}.conf"
else
    source "${PROJECT_DIR}/config.env"
fi

export IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
export EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
export VARIANT="${VARIANT:-base}"

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
export ARCH

# Discover suites
SUITES_DIR="${SCRIPT_DIR}/suites"
available_suites() {
    local suites=()
    for f in "${SUITES_DIR}/"*.sh; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .sh)
        # Skip variant-specific suites that don't match
        if [[ "$name" == variant-* ]]; then
            local vname="${name#variant-}"
            if [[ "${vname}" != "${VARIANT}" ]]; then
                continue
            fi
        fi
        suites+=("$name")
    done
    printf '%s\n' "${suites[@]}"
}

if ${LIST_ONLY}; then
    echo "Available test suites for variant '${VARIANT}':"
    available_suites | while read -r s; do
        echo "  ${s}"
    done
    exit 0
fi

# Must be root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

# Find tarball
TARBALL="${PROJECT_DIR}/images/${IMAGE_NAME}.tar.zst"
if [[ ! -f "${TARBALL}" ]]; then
    echo "ERROR: Tarball not found: ${TARBALL}" >&2
    echo "Build the '${VARIANT}' variant first: sudo ./build.sh --variant ${VARIANT}" >&2
    exit 1
fi

# Extract to temp dir
export ROOTFS
ROOTFS=$(mktemp -d /tmp/nspawn-test.XXXXXX)
cleanup() {
    umount -lf "${ROOTFS}/proc" 2>/dev/null || true
    umount -lf "${ROOTFS}/sys" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev" 2>/dev/null || true
    rm -rf "${ROOTFS}"
}
trap cleanup EXIT

echo "Extracting ${TARBALL} -> ${ROOTFS}"
zstd -d < "${TARBALL}" | tar -C "${ROOTFS}" -xf -

# Mount for chroot operations
mount --bind /dev "${ROOTFS}/dev" 2>/dev/null || true
mount --bind /dev/pts "${ROOTFS}/dev/pts" 2>/dev/null || true
mount -t proc proc "${ROOTFS}/proc" 2>/dev/null || true
mount -t sysfs sys "${ROOTFS}/sys" 2>/dev/null || true

# Source the test library
source "${SCRIPT_DIR}/lib.sh"

echo ""
echo "=== Testing image: ${IMAGE_NAME} (variant: ${VARIANT}) ==="

# Run suites
for suite_name in $(available_suites); do
    if [[ -n "${SUITE_FILTER}" && "${suite_name}" != "${SUITE_FILTER}" ]]; then
        continue
    fi
    suite_file="${SUITES_DIR}/${suite_name}.sh"
    if [[ -f "${suite_file}" ]]; then
        source "${suite_file}"
    fi
done

# Summary
tap_summary
