#!/bin/bash
set -euo pipefail

# Push a built nspawn image tarball to GitHub Container Registry (GHCR)
# as an OCI artifact using ORAS.
#
# Usage:
#   ./ghcr-push.sh [--tag <tag>]
#
# Requires:
#   - GHCR_TOKEN env var (a GitHub PAT or GITHUB_TOKEN with packages:write)
#   - oras CLI (https://oras.land) — auto-installed if missing
#
# The image is pushed as an OCI artifact with media type
# application/vnd.nspawn.image.v1.tar+zstd, making it pullable with
# ghcr-pull.sh or any ORAS-compatible client.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"
GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
GHCR_TAG="${GHCR_TAG:-latest}"
TARBALL="${SCRIPT_DIR}/images/${IMAGE_NAME}.tar.zst"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) GHCR_TAG="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Derive GHCR_REPO from git remote if not set
if [[ -z "${GHCR_REPO}" ]]; then
    REMOTE_URL=$(git -C "${SCRIPT_DIR}" remote get-url origin 2>/dev/null || true)
    if [[ -z "${REMOTE_URL}" ]]; then
        echo "ERROR: GHCR_REPO not set and no git remote found." >&2
        echo "Set GHCR_REPO in config.env or pass via environment." >&2
        exit 1
    fi
    # Extract owner/repo from git URL (handles both HTTPS and SSH)
    OWNER_REPO=$(echo "${REMOTE_URL}" | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
    GHCR_REPO="${OWNER_REPO}/${IMAGE_NAME}"
fi

FULL_REF="${GHCR_REGISTRY}/${GHCR_REPO}:${GHCR_TAG}"

# Validate
if [[ ! -f "${TARBALL}" ]]; then
    echo "ERROR: Tarball not found: ${TARBALL}" >&2
    echo "Run build.sh first." >&2
    exit 1
fi

if [[ -z "${GHCR_TOKEN:-}" ]]; then
    echo "ERROR: GHCR_TOKEN environment variable is required." >&2
    echo "Generate a PAT with packages:write scope, or use GITHUB_TOKEN in CI." >&2
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
        | tar -xz -C /usr/local/bin oras
    echo "oras ${ORAS_VERSION} installed." >&2
fi

# Login to GHCR
echo "${GHCR_TOKEN}" | oras login "${GHCR_REGISTRY}" --username "_token" --password-stdin

# Push the tarball as an OCI artifact
echo "Pushing ${TARBALL} -> ${FULL_REF}"
TARBALL_DIR="$(dirname "${TARBALL}")"
TARBALL_NAME="$(basename "${TARBALL}")"
pushd "${TARBALL_DIR}" > /dev/null
oras push "${FULL_REF}" \
    --artifact-type "application/vnd.nspawn.image.v1" \
    "${TARBALL_NAME}:application/vnd.nspawn.image.v1.tar+zstd"
popd > /dev/null

SIZE=$(du -h "${TARBALL}" | cut -f1)
echo "Done! Pushed ${IMAGE_NAME} (${SIZE}) to ${FULL_REF}"
