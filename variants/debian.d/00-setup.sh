#!/bin/bash
set -euo pipefail

echo "[customize] Debian-specific setup"

# Override hostname for the Debian variant
echo 'nspawn-debian' > /etc/hostname

echo "[customize] Debian setup complete"
