#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

MODE="boot"
IMAGE_NAME="${IMAGE_NAME:-nspawn-base}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --shell) MODE="shell"; shift ;;
        *) IMAGE_NAME="$1"; shift ;;
    esac
done

MACHINE_DIR="/var/lib/machines/${IMAGE_NAME}"

if [[ ! -d "${MACHINE_DIR}" ]]; then
    echo "ERROR: Machine directory not found: ${MACHINE_DIR}" >&2
    echo "Run import.sh first, or extract manually." >&2
    exit 1
fi

if [[ "${MODE}" == "shell" ]]; then
    echo "Starting shell in ${IMAGE_NAME}..."
    exec systemd-nspawn -D "${MACHINE_DIR}"
else
    echo "Booting ${IMAGE_NAME}..."
    exec systemd-nspawn -bD "${MACHINE_DIR}"
fi
