#!/bin/bash
set -euo pipefail

echo "[customize] NVIDIA GPU driver setup for Ubuntu Noble"

# Set hostname
echo 'nspawn-ubuntu-noble-nvidia-560' > /etc/hostname

# Install prerequisites for adding repositories
apt-get update -qq
apt-get install -y --no-install-recommends gpg curl ca-certificates

# Detect architecture for NVIDIA repository
ARCH=$(dpkg --print-architecture)
case "${ARCH}" in
    amd64)  NVIDIA_ARCH="x86_64" ;;
    arm64)  NVIDIA_ARCH="sbsa" ;;  # Server Base System Architecture for ARM64
    *)
        echo "ERROR: Unsupported architecture for NVIDIA drivers: ${ARCH}" >&2
        exit 1
        ;;
esac

echo "[customize] Configuring NVIDIA repository for architecture: ${NVIDIA_ARCH}"

# Add the NVIDIA CUDA repository GPG key
curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVIDIA_ARCH}/3bf863cc.pub" \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-keyring.gpg

# Add the NVIDIA CUDA repository for Ubuntu 24.04 (Noble)
cat > /etc/apt/sources.list.d/nvidia-cuda.list <<EOF
deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVIDIA_ARCH} /
EOF

# Update and install NVIDIA userspace packages
# In a container/nspawn environment we skip kernel modules (no DKMS)
apt-get update -qq
apt-get install -y --no-install-recommends \
    nvidia-headless-no-dkms-560 \
    nvidia-utils-560 \
    libnvidia-compute-560

echo "[customize] NVIDIA GPU setup complete"
