#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Must be root ---
if [[ $(id -u) -ne 0 ]]; then
    echo "Error: this script must be run as root." >&2
    exit 1
fi

# --- Load config defaults ---
IMAGE_NAME="nspawn-base"
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# --- Parse flags ---
SHELL_MODE=false
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --shell)
            SHELL_MODE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--shell] [image-name]" >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
    IMAGE_NAME="${POSITIONAL[0]}"
fi

# --- Validate machine directory ---
MACHINE_DIR="/var/lib/machines/${IMAGE_NAME}"
if [[ ! -d "${MACHINE_DIR}" ]]; then
    echo "Error: machine directory not found: ${MACHINE_DIR}" >&2
    echo "Run import.sh first." >&2
    exit 1
fi

# --- Launch ---
if [[ "${SHELL_MODE}" == true ]]; then
    echo "Starting shell in ${MACHINE_DIR}"
    exec systemd-nspawn -D "${MACHINE_DIR}"
else
    echo "Booting ${MACHINE_DIR}"
    exec systemd-nspawn -bD "${MACHINE_DIR}"
fi
