#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Argument parsing ---
VARIANT=""
BUILD_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --all)     BUILD_ALL=true; shift ;;
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
            echo "Usage: $0 [--variant <name>] [--all] [--list-variants]"
            echo ""
            echo "Options:"
            echo "  --variant <name>   Build a specific variant (loads variants/<name>.conf)"
            echo "  --all              Build all variants"
            echo "  --list-variants    List available variants and exit"
            echo ""
            echo "Without --variant, builds using config.env defaults."
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
        "$0" --variant "${name}"
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

log "=== Building nspawn image: ${IMAGE_NAME} ==="
[[ -n "${VARIANT}" ]] && log "Variant: ${VARIANT}"
log "Distro: ${BASE_DISTRO}  Mirror: ${BASE_MIRROR}"
log "Extra packages: ${EXTRA_PACKAGES}"
log "Rootfs: ${ROOTFS}"

# Step 1: debootstrap
log "Step 1/5: debootstrap"
debootstrap --variant=minbase "${BASE_DISTRO}" "${ROOTFS}" "${BASE_MIRROR}"

# Step 2: Configure apt sources
log "Step 2/5: Configure apt & install extra packages"
DISTRO_FAMILY="${DISTRO_FAMILY:-ubuntu}"
if [[ "${DISTRO_FAMILY}" == "debian" ]]; then
    cat > "${ROOTFS}/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: ${BASE_MIRROR}
Suites: ${BASE_DISTRO} ${BASE_DISTRO}-updates ${BASE_DISTRO}-security
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
chroot "${ROOTFS}" apt-get clean 2>/dev/null || true
rm -rf "${ROOTFS}/var/lib/apt/lists/"* "${ROOTFS}/var/cache/apt/"* "${ROOTFS}/tmp/"*

# Step 5: Pack
log "Step 5/5: Packing tarball"
mkdir -p "${SCRIPT_DIR}/images"
OUTPUT="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"
tar -C "${ROOTFS}" -cf - . | zstd -T0 -9 > "${OUTPUT}"

SIZE=$(du -h "${OUTPUT}" | cut -f1)
log "=== Done! Image: ${OUTPUT} (${SIZE}) ==="
