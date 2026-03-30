#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Argument parsing ---
VARIANT=""
BUILD_ALL=false
ARCH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --all)     BUILD_ALL=true; shift ;;
        --arch)    ARCH="$2"; shift 2 ;;
        --list-variants)
            echo "Available variants:"
            for f in "${SCRIPT_DIR}/variants/"*.conf; do
                [[ -f "$f" ]] || continue
                name=$(basename "$f" .conf)
                desc=$(head -1 "$f" | sed 's/^# *//')
                printf "  %-12s %s\n" "${name}" "${desc}"
            done
            exit 0
            ;;
        -h|--help)
            echo "Usage: $0 [--variant <name>] [--all] [--arch <arch>] [--list-variants]"
            echo ""
            echo "Options:"
            echo "  --variant <name>   Build a specific variant (loads variants/<name>.conf)"
            echo "  --all              Build all variants"
            echo "  --arch <arch>      Target architecture (amd64, arm64; default: host arch)"
            echo "  --list-variants    List available variants and exit"
            echo ""
            echo "Without --variant, builds using config.env defaults."
            echo "Supported architectures: amd64 (x86_64), arm64 (aarch64)"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

# --- Build all variants ---
if ${BUILD_ALL}; then
    for f in "${SCRIPT_DIR}/variants/"*.conf; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f" .conf)
        log "=== Building variant: ${name} ==="
        if [[ -n "${ARCH}" ]]; then
            "$0" --variant "${name}" --arch "${ARCH}"
        else
            "$0" --variant "${name}"
        fi
    done
    exit 0
fi

# --- Load configuration ---
if [[ -n "${VARIANT}" ]]; then
    VARIANT_CONF="${SCRIPT_DIR}/variants/${VARIANT}.conf"
    if [[ ! -f "${VARIANT_CONF}" ]]; then
        echo "ERROR: Variant config not found: ${VARIANT_CONF}" >&2
        echo "Use --list-variants to see available variants." >&2
        exit 1
    fi
    source "${VARIANT_CONF}"
else
    source "${SCRIPT_DIR}/config.env"
fi

IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
BASE_DISTRO="${BASE_DISTRO:-noble}"
BASE_MIRROR="${BASE_MIRROR:-http://archive.ubuntu.com/ubuntu}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-curl wget vim}"

# --- Architecture detection and normalization ---
if [[ -z "${ARCH}" ]]; then
    # Detect host architecture
    HOST_ARCH=$(uname -m)
    case "${HOST_ARCH}" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            echo "ERROR: Unsupported host architecture: ${HOST_ARCH}" >&2
            echo "Supported: x86_64 (amd64), aarch64 (arm64)" >&2
            exit 1
            ;;
    esac
    log "Auto-detected architecture: ${ARCH} (${HOST_ARCH})"
else
    # Normalize user-provided architecture
    case "${ARCH}" in
        amd64|x86_64)  ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)
            echo "ERROR: Unsupported architecture: ${ARCH}" >&2
            echo "Supported: amd64 (x86_64), arm64 (aarch64)" >&2
            exit 1
            ;;
    esac
fi

# Map to debootstrap architecture names
case "${ARCH}" in
    amd64) DEBOOTSTRAP_ARCH="amd64" ;;
    arm64) DEBOOTSTRAP_ARCH="arm64" ;;
esac

# Check for cross-architecture build requirements
HOST_ARCH=$(uname -m)
CROSS_BUILD=false
if [[ "${HOST_ARCH}" == "x86_64" && "${ARCH}" == "arm64" ]] || \
   [[ "${HOST_ARCH}" == "aarch64" && "${ARCH}" == "amd64" ]]; then
    CROSS_BUILD=true
    log "Cross-architecture build detected: ${HOST_ARCH} -> ${ARCH}"
    # Verify QEMU user static is available
    if ! command -v qemu-aarch64-static &>/dev/null && [[ "${ARCH}" == "arm64" ]]; then
        echo "ERROR: qemu-aarch64-static not found" >&2
        echo "For cross-architecture builds, install qemu-user-static:" >&2
        echo "  sudo apt-get install qemu-user-static binfmt-support" >&2
        exit 1
    fi
    if ! command -v qemu-x86_64-static &>/dev/null && [[ "${ARCH}" == "amd64" ]]; then
        echo "ERROR: qemu-x86_64-static not found" >&2
        echo "For cross-architecture builds, install qemu-user-static:" >&2
        echo "  sudo apt-get install qemu-user-static binfmt-support" >&2
        exit 1
    fi
fi

# Append architecture to image name if not default
if [[ "${ARCH}" != "amd64" ]]; then
    IMAGE_NAME="${IMAGE_NAME}-${ARCH}"
fi

# Adjust mirror for Ubuntu ARM64 BEFORE debootstrap
DISTRO_FAMILY="${DISTRO_FAMILY:-ubuntu}"
if [[ "${DISTRO_FAMILY}" == "ubuntu" && "${ARCH}" == "arm64" && "${BASE_MIRROR}" == "http://archive.ubuntu.com/ubuntu" ]]; then
    BASE_MIRROR="http://ports.ubuntu.com/ubuntu-ports"
    log "Using ARM64 mirror: ${BASE_MIRROR}"
fi

ROOTFS=$(mktemp -d /tmp/nspawn-rootfs.XXXXXX)
cleanup() {
    log "Cleaning up ${ROOTFS}..."
    umount -lf "${ROOTFS}/proc" 2>/dev/null || true
    umount -lf "${ROOTFS}/sys" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev" 2>/dev/null || true
    rm -rf "${ROOTFS}"
}
trap cleanup EXIT

# Adjust mirror for Ubuntu ARM64 before debootstrap
DISTRO_FAMILY="${DISTRO_FAMILY:-ubuntu}"
if [[ "${DISTRO_FAMILY}" == "ubuntu" && "${ARCH}" == "arm64" && "${BASE_MIRROR}" == "http://archive.ubuntu.com/ubuntu" ]]; then
    BASE_MIRROR="http://ports.ubuntu.com/ubuntu-ports"
fi

log "=== Building nspawn image: ${IMAGE_NAME} ==="
[[ -n "${VARIANT}" ]] && log "Variant: ${VARIANT}"
log "Architecture: ${ARCH} (${DEBOOTSTRAP_ARCH})"
log "Distro: ${BASE_DISTRO}  Mirror: ${BASE_MIRROR}"
log "Extra packages: ${EXTRA_PACKAGES}"
log "Rootfs: ${ROOTFS}"
if ${CROSS_BUILD}; then
    log "Cross-build mode enabled"
fi

# Step 1: debootstrap
log "Step 1/5: debootstrap"
debootstrap --variant=minbase --arch="${DEBOOTSTRAP_ARCH}" "${BASE_DISTRO}" "${ROOTFS}" "${BASE_MIRROR}"

# Copy QEMU static binary for cross-architecture builds
if ${CROSS_BUILD}; then
    log "Setting up QEMU emulation for cross-build"
    if [[ "${ARCH}" == "arm64" ]]; then
        QEMU_BIN="/usr/bin/qemu-aarch64-static"
    else
        QEMU_BIN="/usr/bin/qemu-x86_64-static"
    fi
    cp "${QEMU_BIN}" "${ROOTFS}${QEMU_BIN}"
fi

# Step 2: Configure apt sources
log "Step 2/5: Configure apt & install extra packages"

if [[ "${DISTRO_FAMILY}" == "debian" ]]; then
    # Debian main + updates
    cat > "${ROOTFS}/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: ${BASE_MIRROR}
Suites: ${BASE_DISTRO} ${BASE_DISTRO}-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    # Debian security uses a separate mirror and suite naming convention
    cat >> "${ROOTFS}/etc/apt/sources.list.d/debian.sources" <<EOF

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${BASE_DISTRO}-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
else
    cat > "${ROOTFS}/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: ${BASE_MIRROR}
Suites: ${BASE_DISTRO} ${BASE_DISTRO}-updates ${BASE_DISTRO}-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi

# Mount necessary filesystems for chroot
mount --bind /dev "${ROOTFS}/dev"
mount --bind /dev/pts "${ROOTFS}/dev/pts"
mount -t proc proc "${ROOTFS}/proc"
mount -t sysfs sys "${ROOTFS}/sys"

# Configure DNS in chroot
cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf" 2>/dev/null || true

chroot "${ROOTFS}" apt-get update -qq
# shellcheck disable=SC2086
chroot "${ROOTFS}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus ${EXTRA_PACKAGES}

# Step 3: Run customize scripts
log "Step 3/5: Running customize scripts"

# Helper to run a directory of scripts inside the rootfs
run_customize_dir() {
    local src_dir="$1"
    local label="$2"
    if [[ -d "${src_dir}" ]] && ls "${src_dir}/"*.sh &>/dev/null; then
        cp -r "${src_dir}" "${ROOTFS}/tmp/_customize"
        chmod +x "${ROOTFS}/tmp/_customize/"*.sh
        for script in "${ROOTFS}/tmp/_customize/"*.sh; do
            name=$(basename "$script")
            log "  [${label}] Running ${name}..."
            chroot "${ROOTFS}" /bin/bash "/tmp/_customize/${name}"
        done
        rm -rf "${ROOTFS}/tmp/_customize"
    else
        log "  [${label}] No scripts found, skipping."
    fi
}

# Always run base customize.d/ first
run_customize_dir "${SCRIPT_DIR}/customize.d" "base"

# Then run variant-specific scripts
if [[ -n "${VARIANT}" ]]; then
    VARIANT_CUSTOMIZE="${SCRIPT_DIR}/variants/${VARIANT}.d"
    run_customize_dir "${VARIANT_CUSTOMIZE}" "${VARIANT}"
fi

# Step 4: Clean up
log "Step 4/5: Cleaning caches"
umount -lf "${ROOTFS}/proc" 2>/dev/null || true
umount -lf "${ROOTFS}/sys" 2>/dev/null || true
umount -lf "${ROOTFS}/dev/pts" 2>/dev/null || true
umount -lf "${ROOTFS}/dev" 2>/dev/null || true
# Remove QEMU static binary if it was copied for cross-build
if ${CROSS_BUILD}; then
    if [[ "${ARCH}" == "arm64" ]]; then
        rm -f "${ROOTFS}/usr/bin/qemu-aarch64-static"
    else
        rm -f "${ROOTFS}/usr/bin/qemu-x86_64-static"
    fi
fi
chroot "${ROOTFS}" apt-get clean 2>/dev/null || true
rm -rf "${ROOTFS}/var/lib/apt/lists/"* "${ROOTFS}/var/cache/apt/"* "${ROOTFS}/tmp/"*

# Step 5: Pack
log "Step 5/5: Packing tarball"
mkdir -p "${SCRIPT_DIR}/images"
OUTPUT="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"
tar -C "${ROOTFS}" -cf - . | zstd -T0 -9 > "${OUTPUT}"

SIZE=$(du -h "${OUTPUT}" | cut -f1)
log "=== Done! Image: ${OUTPUT} (${SIZE}) ==="
