#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Must be root ---
if [[ $(id -u) -ne 0 ]]; then
    echo "Error: this script must be run as root." >&2
    exit 1
fi

# --- Validate args ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 s3://bucket/path/image-name.tar.zst" >&2
    exit 1
fi

S3_URL="$1"

# --- Derive image name from URL ---
FILENAME="$(basename "${S3_URL}")"
if [[ "${FILENAME}" != *.tar.zst ]]; then
    echo "Error: expected a .tar.zst URL, got: ${S3_URL}" >&2
    exit 1
fi
IMAGE_NAME="${FILENAME%.tar.zst}"

# --- Download ---
mkdir -p "${SCRIPT_DIR}/images"
LOCAL_TARBALL="${SCRIPT_DIR}/images/${FILENAME}"

if command -v aws &>/dev/null; then
    echo "Downloading ${S3_URL} → ${LOCAL_TARBALL}  (aws cli)"
    aws s3 cp "${S3_URL}" "${LOCAL_TARBALL}"
elif command -v mc &>/dev/null; then
    echo "Downloading ${S3_URL} → ${LOCAL_TARBALL}  (mc)"
    mc cp "${S3_URL}" "${LOCAL_TARBALL}"
else
    echo "Error: neither 'aws' nor 'mc' found in PATH." >&2
    exit 1
fi

# --- Extract into /var/lib/machines/<image-name> ---
MACHINE_DIR="/var/lib/machines/${IMAGE_NAME}"
mkdir -p "${MACHINE_DIR}"

echo "Extracting ${LOCAL_TARBALL} → ${MACHINE_DIR}"
tar -C "${MACHINE_DIR}" -xf "${LOCAL_TARBALL}" --zstd

echo "Imported: ${MACHINE_DIR}"
