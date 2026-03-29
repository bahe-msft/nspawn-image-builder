# nspawn-image-builder

Build portable, reproducible systemd-nspawn container images with S3 export/import.

## Quick Start

```bash
# 1. Edit config.env for your needs (packages, image name, etc.)
# 2. Drop custom scripts into customize.d/ (they run in sorted order)
# 3. Build
sudo ./build.sh

# 4. Validate
sudo ./validate.sh

# 5. Export to S3
./export.sh s3://my-bucket/images/

# 6. On another VM: import and run
sudo ./import.sh s3://my-bucket/images/nspawn-base.tar.zst
sudo ./run.sh              # boot mode
sudo ./run.sh --shell      # interactive shell
```

## Customization

Add shell scripts to `customize.d/`. They run inside the rootfs via `chroot` during build, sorted by filename. Example:

```bash
# customize.d/10-install-docker.sh
#!/bin/bash
apt-get install -y docker.io
touch /etc/nspawn-customized
```

The `00-base-setup.sh` script handles timezone, networking, and creates the `/etc/nspawn-customized` marker file.

## Files

| File | Description |
|------|-------------|
| `config.env` | Image name, distro, mirror, extra packages |
| `customize.d/` | Drop-in scripts run inside the image during build |
| `build.sh` | Builds rootfs + packs tarball |
| `export.sh` | Uploads tarball to S3 |
| `import.sh` | Downloads from S3 + extracts to /var/lib/machines/ |
| `run.sh` | Launches container via systemd-nspawn |
| `validate.sh` | End-to-end validation of built image |

## Dependencies

`debootstrap`, `systemd-container`, `zstd`, and optionally `awscli` or `mc` for S3.
