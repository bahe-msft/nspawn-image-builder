#!/bin/bash
set -euo pipefail

echo "[customize] NVIDIA GPU driver setup for Ubuntu Noble"

# Set hostname
echo 'nspawn-ubuntu-noble-nvidia-560' > /etc/hostname

# Install prerequisites for adding repositories
apt-get update -qq
apt-get install -y --no-install-recommends gpg curl ca-certificates

# Add the NVIDIA CUDA repository GPG key
curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-keyring.gpg

# Add the NVIDIA CUDA repository for Ubuntu 24.04 (Noble)
cat > /etc/apt/sources.list.d/nvidia-cuda.list <<'EOF'
deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64 /
EOF

# Update and install NVIDIA userspace packages
# In a container/nspawn environment we skip kernel modules (no DKMS)
apt-get update -qq
apt-get install -y --no-install-recommends \
    nvidia-headless-no-dkms-560 \
    nvidia-utils-560 \
    libnvidia-compute-560

echo "[customize] NVIDIA GPU setup complete"
