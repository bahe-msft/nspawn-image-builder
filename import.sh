#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 s3://bucket/path/image-name.tar.zst" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S3_SRC="$1"
FILENAME=$(basename "${S3_SRC}")
IMAGE_NAME="${FILENAME%.tar.zst}"

mkdir -p "${SCRIPT_DIR}/images"
LOCAL_TAR="${SCRIPT_DIR}/images/${FILENAME}"

# Download
echo "Downloading ${S3_SRC} -> ${LOCAL_TAR}"
if command -v aws &>/dev/null; then
    aws s3 cp "${S3_SRC}" "${LOCAL_TAR}"
elif command -v mc &>/dev/null; then
    mc cp "${S3_SRC}" "${LOCAL_TAR}"
else
    echo "ERROR: Neither 'aws' nor 'mc' CLI found." >&2
    exit 1
fi

# Extract
MACHINE_DIR="/var/lib/machines/${IMAGE_NAME}"
echo "Extracting to ${MACHINE_DIR}"
mkdir -p "${MACHINE_DIR}"
zstd -d < "${LOCAL_TAR}" | tar -C "${MACHINE_DIR}" -xf -

echo "Done! Machine '${IMAGE_NAME}' ready at ${MACHINE_DIR}"
echo "Boot with: sudo systemd-nspawn -bD ${MACHINE_DIR}"
echo "Shell with: sudo systemd-nspawn -D ${MACHINE_DIR}"
