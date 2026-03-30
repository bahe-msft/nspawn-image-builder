#!/bin/bash
set -euo pipefail

# Pull an nspawn image from GitHub Container Registry (GHCR) and
# optionally extract it to /var/lib/machines/ for immediate use.
#
# Usage:
#   ./ghcr-pull.sh [--tag <tag>] [--extract]
#
# With --extract (requires root), the image is unpacked into
# /var/lib/machines/<IMAGE_NAME> ready for systemd-nspawn.
#
# Requires:
#   - GHCR_TOKEN env var (a GitHub PAT or GITHUB_TOKEN with packages:read)
#     For public packages, GHCR_TOKEN is optional.
#   - oras CLI (https://oras.land) — auto-installed if missing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
GHCR_TAG="${GHCR_TAG:-latest}"
EXTRACT=false

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) GHCR_TAG="$2"; shift 2 ;;
        --extract) EXTRACT=true; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Derive GHCR_REPO from git remote if not set
if [[ -z "${GHCR_REPO}" ]]; then
    REMOTE_URL=$(git -C "${SCRIPT_DIR}" remote get-url origin 2>/dev/null || true)
    if [[ -z "${REMOTE_URL}" ]]; then
        echo "ERROR: GHCR_REPO not set and no git remote found." >&2
        exit 1
    fi
    OWNER_REPO=$(echo "${REMOTE_URL}" | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
    GHCR_REPO="${OWNER_REPO}/${IMAGE_NAME}"
fi

FULL_REF="${GHCR_REGISTRY}/${GHCR_REPO}:${GHCR_TAG}"

if ${EXTRACT} && [[ $EUID -ne 0 ]]; then
    echo "ERROR: --extract requires root" >&2
    exit 1
fi

# Ensure oras is available
if ! command -v oras &>/dev/null; then
    echo "oras CLI not found. Installing..." >&2
    ORAS_VERSION="1.2.2"
    ORAS_ARCH=$(uname -m)
    case "${ORAS_ARCH}" in
        x86_64) ORAS_ARCH="amd64" ;;
        aarch64) ORAS_ARCH="arm64" ;;
    esac
    curl -fsSL "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${ORAS_ARCH}.tar.gz" \
        | sudo tar -xz -C /usr/local/bin oras
    echo "oras ${ORAS_VERSION} installed." >&2
fi

# Login to GHCR (optional for public packages)
if [[ -n "${GHCR_TOKEN:-}" ]]; then
    echo "${GHCR_TOKEN}" | oras login "${GHCR_REGISTRY}" --username "_token" --password-stdin
else
    echo "Warning: GHCR_TOKEN not set. Pull will only work for public packages." >&2
fi

# Pull
mkdir -p "${SCRIPT_DIR}/images"
OUTPUT_DIR="${SCRIPT_DIR}/images"

echo "Pulling ${FULL_REF}..."
oras pull "${FULL_REF}" --output "${OUTPUT_DIR}"

# The pulled file will be the tarball
TARBALL="${OUTPUT_DIR}/${IMAGE_NAME}.tar.zst"
if [[ ! -f "${TARBALL}" ]]; then
    # oras may preserve the original path; find it
    TARBALL=$(find "${OUTPUT_DIR}" -name '*.tar.zst' -newer "${SCRIPT_DIR}/config.env" | head -1)
    if [[ -z "${TARBALL}" ]]; then
        echo "ERROR: Could not find downloaded tarball in ${OUTPUT_DIR}" >&2
        exit 1
    fi
fi

SIZE=$(du -h "${TARBALL}" | cut -f1)
echo "Downloaded: ${TARBALL} (${SIZE})"

# Extract if requested
if ${EXTRACT}; then
    MACHINE_DIR="/var/lib/machines/${IMAGE_NAME}"
    echo "Extracting to ${MACHINE_DIR}..."
    mkdir -p "${MACHINE_DIR}"
    zstd -d < "${TARBALL}" | tar -C "${MACHINE_DIR}" -xf -
    echo "Machine '${IMAGE_NAME}' ready at ${MACHINE_DIR}"
    echo "Boot with: sudo systemd-nspawn -bD ${MACHINE_DIR}"
    echo "Shell with: sudo systemd-nspawn -D ${MACHINE_DIR}"
else
    echo "To extract and register the machine, run:"
    echo "  sudo ./ghcr-pull.sh --extract"
    echo "Or manually:"
    echo "  sudo mkdir -p /var/lib/machines/${IMAGE_NAME}"
    echo "  sudo zstd -d < ${TARBALL} | sudo tar -C /var/lib/machines/${IMAGE_NAME} -xf -"
fi
