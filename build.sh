#!/usr/bin/env bash
#
# build.sh — Build a systemd-nspawn container image from scratch.
#
# Creates a minimal Ubuntu rootfs via debootstrap, applies customization
# scripts, and packs everything into a zstd-compressed tarball.
#
set -euo pipefail

###############################################################################
# Logging
###############################################################################
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "FATAL: $*" >&2
    exit 1
}

###############################################################################
# Root check
###############################################################################
if [[ "$(id -u)" -ne 0 ]]; then
    die "This script must be run as root."
fi

###############################################################################
# Resolve script directory & source config
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
IMAGE_NAME="nspawn-base"
BASE_DISTRO="noble"
BASE_MIRROR="http://archive.ubuntu.com/ubuntu"
EXTRA_PACKAGES="curl wget vim less htop net-tools iputils-ping dnsutils"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    log "Sourcing ${SCRIPT_DIR}/config.env"
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
else
    log "No config.env found — using defaults."
fi

log "IMAGE_NAME=${IMAGE_NAME}"
log "BASE_DISTRO=${BASE_DISTRO}"
log "BASE_MIRROR=${BASE_MIRROR}"
log "EXTRA_PACKAGES=${EXTRA_PACKAGES}"

###############################################################################
# Temp directory + cleanup trap
###############################################################################
ROOTFS_DIR=""

cleanup() {
    if [[ -n "${ROOTFS_DIR}" && -d "${ROOTFS_DIR}" ]]; then
        log "Cleaning up temporary rootfs at ${ROOTFS_DIR}"
        # Unmount any leftover bind mounts (best-effort)
        for mp in "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/dev/pts" "${ROOTFS_DIR}/dev"; do
            mountpoint -q "${mp}" 2>/dev/null && umount -l "${mp}" 2>/dev/null || true
        done
        rm -rf "${ROOTFS_DIR}"
        log "Temporary rootfs removed."
    fi
}
trap cleanup EXIT

ROOTFS_DIR="$(mktemp -d /tmp/nspawn-rootfs.XXXXXXXXXX)"
log "Temporary rootfs directory: ${ROOTFS_DIR}"

###############################################################################
# Stage 1 — debootstrap
###############################################################################
log "Running debootstrap for ${BASE_DISTRO} from ${BASE_MIRROR} ..."
debootstrap --variant=minbase "${BASE_DISTRO}" "${ROOTFS_DIR}" "${BASE_MIRROR}"
log "debootstrap completed successfully."

###############################################################################
# Stage 2 — Install extra packages
###############################################################################
if [[ -n "${EXTRA_PACKAGES}" ]]; then
    log "Installing extra packages: ${EXTRA_PACKAGES}"

    # Make sure DNS resolution works inside the chroot
    cp -L /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true

    chroot "${ROOTFS_DIR}" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends ${EXTRA_PACKAGES}
    "
    log "Extra packages installed."
fi

###############################################################################
# Stage 3 — Run customization scripts
###############################################################################
CUSTOMIZE_SRC="${SCRIPT_DIR}/customize.d"

if [[ -d "${CUSTOMIZE_SRC}" ]]; then
    log "Copying customize.d/ scripts into rootfs ..."
    mkdir -p "${ROOTFS_DIR}/tmp/customize.d"
    cp -a "${CUSTOMIZE_SRC}/"* "${ROOTFS_DIR}/tmp/customize.d/" 2>/dev/null || true

    # Run each *.sh script in sorted order
    SCRIPTS=( $(find "${ROOTFS_DIR}/tmp/customize.d" -maxdepth 1 -name '*.sh' -printf '%f\n' | sort) )

    if [[ ${#SCRIPTS[@]} -gt 0 ]]; then
        for script in "${SCRIPTS[@]}"; do
            log "Running customize script: ${script}"
            chroot "${ROOTFS_DIR}" /bin/bash "/tmp/customize.d/${script}"
            log "Finished: ${script}"
        done
    else
        log "No *.sh scripts found in customize.d/ — skipping."
    fi
else
    log "No customize.d/ directory found — skipping customization."
fi

###############################################################################
# Stage 4 — Cleanup inside rootfs
###############################################################################
log "Cleaning up rootfs ..."
chroot "${ROOTFS_DIR}" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    rm -rf /var/cache/apt/archives/*.deb
    rm -rf /var/cache/apt/archives/partial/*
    rm -rf /tmp/*
    rm -rf /var/tmp/*
"
log "Rootfs cleanup done."

###############################################################################
# Stage 5 — Pack the image
###############################################################################
IMAGES_DIR="${SCRIPT_DIR}/images"
mkdir -p "${IMAGES_DIR}"

OUTPUT="${IMAGES_DIR}/${IMAGE_NAME}.tar.zst"
log "Packing rootfs into ${OUTPUT} ..."
tar -C "${ROOTFS_DIR}" -cf - . | zstd -T0 -9 > "${OUTPUT}"
log "Image created: ${OUTPUT} ($(du -h "${OUTPUT}" | cut -f1))"

log "Build complete."
