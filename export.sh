#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
TARBALL="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 s3://bucket/path/" >&2
    exit 1
fi

S3_DEST="$1"

if [[ ! -f "${TARBALL}" ]]; then
    echo "ERROR: Tarball not found: ${TARBALL}" >&2
    echo "Run build.sh first." >&2
    exit 1
fi

upload() {
    if command -v aws &>/dev/null; then
        aws s3 cp "${TARBALL}" "${S3_DEST}${IMAGE_NAME}.tar.zst"
    elif command -v mc &>/dev/null; then
        mc cp "${TARBALL}" "${S3_DEST}${IMAGE_NAME}.tar.zst"
    else
        echo "ERROR: Neither 'aws' nor 'mc' CLI found. Install one first." >&2
        exit 1
    fi
}

echo "Uploading ${TARBALL} -> ${S3_DEST}${IMAGE_NAME}.tar.zst"
upload
echo "Done! Uploaded to: ${S3_DEST}${IMAGE_NAME}.tar.zst"
