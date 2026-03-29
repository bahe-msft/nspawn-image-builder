#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
BASE_DISTRO="${BASE_DISTRO:-noble}"
BASE_MIRROR="${BASE_MIRROR:-http://archive.ubuntu.com/ubuntu}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-curl wget vim}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

ROOTFS=$(mktemp -d /tmp/nspawn-rootfs.XXXXXX)
cleanup() {
    log "Cleaning up ${ROOTFS}..."
    # unmount any leftover mounts
    umount -lf "${ROOTFS}/proc" 2>/dev/null || true
    umount -lf "${ROOTFS}/sys" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount -lf "${ROOTFS}/dev" 2>/dev/null || true
    rm -rf "${ROOTFS}"
}
trap cleanup EXIT

log "=== Building nspawn image: ${IMAGE_NAME} ==="
log "Distro: ${BASE_DISTRO}  Mirror: ${BASE_MIRROR}"
log "Extra packages: ${EXTRA_PACKAGES}"
log "Rootfs: ${ROOTFS}"

# Step 1: debootstrap
log "Step 1/5: debootstrap"
debootstrap --variant=minbase "${BASE_DISTRO}" "${ROOTFS}" "${BASE_MIRROR}"

# Step 2: Configure apt sources for universe
log "Step 2/5: Configure apt & install extra packages"
cat > "${ROOTFS}/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: ${BASE_MIRROR}
Suites: ${BASE_DISTRO} ${BASE_DISTRO}-updates ${BASE_DISTRO}-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

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
if [[ -d "${SCRIPT_DIR}/customize.d" ]] && ls "${SCRIPT_DIR}/customize.d/"*.sh &>/dev/null; then
    cp -r "${SCRIPT_DIR}/customize.d" "${ROOTFS}/tmp/customize.d"
    chmod +x "${ROOTFS}/tmp/customize.d/"*.sh
    for script in "${ROOTFS}/tmp/customize.d/"*.sh; do
        name=$(basename "$script")
        log "  Running ${name}..."
        chroot "${ROOTFS}" /bin/bash "/tmp/customize.d/${name}"
    done
    rm -rf "${ROOTFS}/tmp/customize.d"
else
    log "  No customize scripts found, skipping."
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
