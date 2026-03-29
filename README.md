# nspawn-image-builder

Portable, reproducible images for `systemd-nspawn` containers, with S3 export/import.

## Quick Start

```bash
# 1. Edit config.env to set image name, distro, packages
# 2. Add customization scripts to customize.d/ (run in sorted order)
# 3. Build the image
sudo ./build.sh            # → images/<IMAGE_NAME>.tar.zst

# 4. Validate
sudo ./validate.sh         # checks rootfs structure, packages, nspawn boot

# 5. Export to S3
./export.sh s3://bucket/path/

# 6. On another VM: import + run
sudo ./import.sh s3://bucket/path/nspawn-base.tar.zst
sudo ./run.sh [--shell] [image-name]
```

## Files

| File | Purpose |
|------|---------|
| `config.env` | Image name, base distro, mirror, extra packages |
| `customize.d/*.sh` | Drop-in scripts run inside the rootfs (sorted order) |
| `build.sh` | Builds rootfs via debootstrap + packs `.tar.zst` |
| `export.sh` | Uploads tarball to S3 (aws cli or mc) |
| `import.sh` | Downloads tarball from S3 + extracts to `/var/lib/machines/` |
| `run.sh` | Launches container via `systemd-nspawn` |
| `validate.sh` | End-to-end validation |

## Dependencies

- `debootstrap`, `systemd-container`, `zstd`
- `awscli` or `mc` (for S3 export/import)

## Configuration

Edit `config.env`:

```bash
IMAGE_NAME="nspawn-base"     # tarball and machine name
BASE_DISTRO="noble"           # Ubuntu release codename
BASE_MIRROR="http://archive.ubuntu.com/ubuntu"
EXTRA_PACKAGES="curl wget vim less htop net-tools iputils-ping dnsutils ca-certificates"
```

## Customization

Drop executable `.sh` scripts into `customize.d/`. They run inside the rootfs
via `chroot` in sorted order. Example: `customize.d/00-base-setup.sh`.
