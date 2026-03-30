#!/bin/bash
set -euo pipefail

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Set locale
echo 'LANG=en_US.UTF-8' > /etc/locale.conf 2>/dev/null || true

# Set hostname
echo 'nspawn-container' > /etc/hostname

# Enable systemd-networkd and systemd-resolved for container networking.
# Use both systemctl and manual symlink creation since systemctl enable
# can be unreliable inside a chroot without a running systemd.
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service 2>/dev/null || true
ln -sf /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service 2>/dev/null || true
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true

# Set root password to empty (login without password)
passwd -d root 2>/dev/null || true

# Leave a marker so validation knows customization ran
touch /etc/nspawn-customized

echo "[customize] Base setup complete."
