#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load config ---
IMAGE_NAME="nspawn-base"
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# --- Validate args ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 s3://bucket/path/" >&2
    exit 1
fi

S3_DEST="$1"

# --- Check tarball exists ---
TARBALL="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"
if [[ ! -f "${TARBALL}" ]]; then
    echo "Error: tarball not found: ${TARBALL}" >&2
    echo "Run build.sh first." >&2
    exit 1
fi

# --- Ensure destination ends with / so we get a clean URL ---
[[ "${S3_DEST}" == */ ]] || S3_DEST="${S3_DEST}/"

# --- Upload ---
S3_URL="${S3_DEST}${IMAGE_NAME}.tar.zst"

if command -v aws &>/dev/null; then
    echo "Uploading ${TARBALL} → ${S3_URL}  (aws cli)"
    aws s3 cp "${TARBALL}" "${S3_URL}"
elif command -v mc &>/dev/null; then
    echo "Uploading ${TARBALL} → ${S3_URL}  (mc)"
    mc cp "${TARBALL}" "${S3_URL}"
else
    echo "Error: neither 'aws' nor 'mc' found in PATH." >&2
    exit 1
fi

echo "Uploaded: ${S3_URL}"
