# nspawn-image-builder

Build portable, reproducible systemd-nspawn container images with variant support, unit tests, S3 export/import, and GHCR publishing.

## Quick Start

```bash
# 1. Build the base image
sudo ./build.sh

# 2. Or build a specific variant
sudo ./build.sh --variant dev
sudo ./build.sh --variant debian

# 3. Build all variants at once
sudo ./build.sh --all

# 4. Validate
sudo ./validate.sh --variant dev

# 5. Run tests
sudo ./tests/run-tests.sh --variant dev

# 6. Export to S3 or GHCR (see below)
```

## Variants

Variants define different image configurations. Each variant has its own packages and customization scripts.

```bash
# List available variants
./build.sh --list-variants
```

| Variant | Image Name | Description |
|---------|------------|-------------|
| `base` | nspawn-base | Minimal Ubuntu Noble system with essential utilities |
| `dev` | nspawn-dev | Development tools: gcc, python3, git, cmake, gdb, tmux |
| `debian` | nspawn-debian | Debian Bookworm base system with essential utilities |

### Creating a Custom Variant

1. Create `variants/<name>.conf` with your configuration:
   ```bash
   IMAGE_NAME="nspawn-myvariant"
   BASE_DISTRO="noble"
   BASE_MIRROR="http://archive.ubuntu.com/ubuntu"
   EXTRA_PACKAGES="curl wget nginx"
   ```

2. Optionally add customization scripts in `variants/<name>.d/`:
   ```bash
   # variants/myvariant.d/00-setup.sh
   #!/bin/bash
   set -euo pipefail
   systemctl enable nginx
   touch /etc/nspawn-customized
   ```

3. Optionally add variant-specific tests in `tests/suites/variant-<name>.sh`.

The base `customize.d/` scripts always run first, then variant-specific ones.

## Testing

A TAP-format test framework validates built images.

```bash
# Run all tests for a variant
sudo ./tests/run-tests.sh --variant base

# Run a specific test suite
sudo ./tests/run-tests.sh --variant dev --suite packages

# List available test suites
./tests/run-tests.sh --variant debian --list
```

### Test Suites

| Suite | What it checks |
|-------|----------------|
| `rootfs` | Directory structure, permissions, clean /tmp, clean apt cache |
| `packages` | All configured packages installed, no broken packages, binaries executable |
| `services` | systemd-networkd/resolved enabled, no broken units |
| `security` | No world-writable files, no unexpected SUID, shadow permissions, no empty passwords |
| `nspawn` | Container execution, /proc and /sys mounted, DNS resolution, os-release readable |
| `variant-*` | Variant-specific checks (e.g., gcc works for dev, Debian distro check for debian) |

## GHCR (GitHub Container Registry)

Images can be published to GHCR as OCI artifacts, either via CI or manually.

### CI (GitHub Actions)

The included workflow automatically:

1. Discovers all variants and builds them in parallel (matrix strategy)
2. Validates each image with `validate.sh`
3. Runs the full test suite for each variant
4. Uploads each tarball as a **GitHub Actions artifact** (retained 30 days)
5. On pushes to `main`: publishes each variant to **GHCR** with commit-SHA and `latest` tags

Use `workflow_dispatch` to build a specific variant or use a custom tag.

### Manual Push / Pull

```bash
# Push
export GHCR_TOKEN="ghp_..."
./ghcr-push.sh --tag v1.0.0

# Pull and deploy
sudo GHCR_TOKEN="ghp_..." ./ghcr-pull.sh --extract
sudo ./run.sh
```

## S3 Export / Import

```bash
./export.sh s3://my-bucket/images/
sudo ./import.sh s3://my-bucket/images/nspawn-base.tar.zst
sudo ./run.sh
sudo ./run.sh --shell  # interactive shell
```

## Customization

Add shell scripts to `customize.d/`. They run inside the rootfs via `chroot` during build, sorted by filename. Example:

```bash
# customize.d/10-install-app.sh
#!/bin/bash
apt-get install -y myapp
touch /etc/nspawn-customized
```

## Files

| File | Description |
|------|-------------|
| `config.env` | Default image configuration |
| `variants/` | Variant configs (`.conf`) and customize scripts (`.d/`) |
| `customize.d/` | Base customize scripts (run for all variants) |
| `build.sh` | Builds rootfs + packs tarball (supports `--variant`, `--all`) |
| `validate.sh` | Quick validation of built image |
| `tests/` | Test framework with TAP output |
| `tests/run-tests.sh` | Test runner (supports `--variant`, `--suite`, `--list`) |
| `tests/suites/` | Individual test suites |
| `export.sh` | Upload tarball to S3 |
| `import.sh` | Download from S3 + extract |
| `ghcr-push.sh` | Push tarball to GHCR as OCI artifact |
| `ghcr-pull.sh` | Pull tarball from GHCR |
| `run.sh` | Launch container via systemd-nspawn |
| `.github/workflows/` | CI: build all variants, test, publish |

## Dependencies

`debootstrap`, `systemd-container`, `zstd`, and optionally:
- `awscli` or `mc` for S3 export/import
- [`oras`](https://oras.land) for GHCR push/pull (auto-installed by scripts if missing)
