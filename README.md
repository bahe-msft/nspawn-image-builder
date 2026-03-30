# nspawn-image-builder

Build portable, reproducible systemd-nspawn container images with S3 export/import and GHCR publishing.

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

## GHCR (GitHub Container Registry)

Images can be published to GHCR as OCI artifacts, either via CI or manually.

### CI (GitHub Actions)

The included workflow (`.github/workflows/build-and-publish.yml`) automatically:

1. Builds the image on every push to `main`
2. Validates it with `validate.sh`
3. Uploads the tarball as a **GitHub Actions artifact** (retained 30 days)
4. Pushes to **GHCR** with both a commit-SHA tag and `latest`

Pull requests build and validate but do not publish.

The workflow uses `GITHUB_TOKEN` for authentication — no extra secrets needed.

### Manual Push

```bash
# Build first
sudo ./build.sh

# Push to GHCR (requires a PAT with packages:write, or GITHUB_TOKEN)
export GHCR_TOKEN="ghp_..."
./ghcr-push.sh                   # pushes as :latest
./ghcr-push.sh --tag v1.0.0      # pushes as :v1.0.0
```

### Pull from GHCR

```bash
# Download tarball to images/
export GHCR_TOKEN="ghp_..."  # optional for public packages
./ghcr-pull.sh

# Download and extract directly to /var/lib/machines/ (requires root)
sudo GHCR_TOKEN="ghp_..." ./ghcr-pull.sh --extract

# Pull a specific tag
./ghcr-pull.sh --tag v1.0.0
```

The image reference defaults to `ghcr.io/<owner>/<repo>/<IMAGE_NAME>` (derived
from the git remote). Override with `GHCR_REPO` in `config.env` or the
environment.

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
| `config.env` | Image name, distro, mirror, extra packages, GHCR settings |
| `customize.d/` | Drop-in scripts run inside the image during build |
| `build.sh` | Builds rootfs + packs tarball |
| `export.sh` | Uploads tarball to S3 |
| `import.sh` | Downloads from S3 + extracts to /var/lib/machines/ |
| `ghcr-push.sh` | Pushes tarball to GHCR as OCI artifact |
| `ghcr-pull.sh` | Pulls tarball from GHCR, optionally extracts |
| `run.sh` | Launches container via systemd-nspawn |
| `validate.sh` | End-to-end validation of built image |
| `.github/workflows/build-and-publish.yml` | CI: build, validate, publish |

## Dependencies

`debootstrap`, `systemd-container`, `zstd`, and optionally:
- `awscli` or `mc` for S3 export/import
- [`oras`](https://oras.land) for GHCR push/pull (auto-installed by scripts if missing)
