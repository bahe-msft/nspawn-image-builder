# ARM64 Testing Guide

This guide covers testing ARM64 support in nspawn-image-builder.

## Prerequisites

For cross-architecture testing on x86_64 hosts:

```bash
sudo apt-get update
sudo apt-get install -y debootstrap systemd-container zstd qemu-user-static binfmt-support
```

## Quick Verification

### 1. Check QEMU Installation

```bash
# Verify QEMU static binaries are available
ls -lh /usr/bin/qemu-*-static

# Check binfmt handlers are registered
ls -lh /proc/sys/fs/binfmt_misc/
```

Expected output should include:
- `/usr/bin/qemu-aarch64-static` (for ARM64 emulation)
- `/proc/sys/fs/binfmt_misc/qemu-aarch64` (binfmt handler)

### 2. Test Architecture Detection

```bash
# Show auto-detected architecture
./build.sh --help

# The script will show "Supported architectures: amd64 (x86_64), arm64 (aarch64)"
```

### 3. Build a Simple ARM64 Image

```bash
# Build Ubuntu Noble for ARM64
sudo ./build.sh --variant ubuntu-noble --arch arm64

# Check the output
ls -lh images/nspawn-ubuntu-noble-arm64.tar.zst
```

### 4. Validate the Build

```bash
# Run validation
sudo ./validate.sh --variant ubuntu-noble --arch arm64

# Should show PASS for all checks
```

### 5. Run Full Test Suite

```bash
# Run all tests for ARM64 build
sudo ./tests/run-tests.sh --variant ubuntu-noble --arch arm64

# Should show TAP test results with all passing
```

## Comprehensive Testing

### Test Matrix

| Test Case | Command | Expected Result |
|-----------|---------|----------------|
| Auto-detect amd64 | `sudo ./build.sh --variant ubuntu-noble` | Builds amd64 image |
| Explicit amd64 | `sudo ./build.sh --variant ubuntu-noble --arch amd64` | Builds amd64 image |
| Explicit arm64 | `sudo ./build.sh --variant ubuntu-noble --arch arm64` | Builds arm64 image (cross) |
| x86_64 alias | `sudo ./build.sh --variant ubuntu-noble --arch x86_64` | Normalized to amd64 |
| aarch64 alias | `sudo ./build.sh --variant ubuntu-noble --arch aarch64` | Normalized to arm64 |
| Invalid arch | `sudo ./build.sh --variant ubuntu-noble --arch riscv64` | Error: unsupported |
| No QEMU (cross) | Uninstall QEMU, try arm64 | Error: qemu-aarch64-static not found |

### Test All Variants

```bash
# Build all variants for AMD64
sudo ./build.sh --all

# Build all variants for ARM64
sudo ./build.sh --all --arch arm64
```

### Test NVIDIA Variant

```bash
# Build NVIDIA variant for both architectures
sudo ./build.sh --variant ubuntu-noble-nvidia-560 --arch amd64
sudo ./build.sh --variant ubuntu-noble-nvidia-560 --arch arm64

# Verify correct repository configuration
sudo tar -xOf images/nspawn-ubuntu-noble-nvidia-560.tar.zst etc/apt/sources.list.d/nvidia-cuda.list
# Should show x86_64 path

sudo tar -xOf images/nspawn-ubuntu-noble-nvidia-560-arm64.tar.zst etc/apt/sources.list.d/nvidia-cuda.list
# Should show sbsa path
```

## Image Inspection

### Check Architecture in Image

```bash
# Extract and inspect the rootfs
mkdir -p /tmp/test-rootfs
sudo zstd -d < images/nspawn-ubuntu-noble-arm64.tar.zst | sudo tar -C /tmp/test-rootfs -xf -

# Check dpkg architecture
sudo chroot /tmp/test-rootfs dpkg --print-architecture
# Should output: arm64

# Check ELF binaries
file /tmp/test-rootfs/bin/bash
# Should show: ELF 64-bit LSB executable, ARM aarch64, ...

# Cleanup
sudo rm -rf /tmp/test-rootfs
```

### Verify No QEMU in Final Image

```bash
# QEMU should NOT be in the final tarball
sudo tar -tzf images/nspawn-ubuntu-noble-arm64.tar.zst | grep -i qemu
# Should return empty (no QEMU binaries)
```

### Check Mirror Configuration

```bash
# ARM64 should use ports.ubuntu.com
sudo tar -xOf images/nspawn-ubuntu-noble-arm64.tar.zst etc/apt/sources.list.d/ubuntu.sources | grep URIs
# Should show: URIs: http://ports.ubuntu.com/ubuntu-ports

# AMD64 should use archive.ubuntu.com
sudo tar -xOf images/nspawn-ubuntu-noble.tar.zst etc/apt/sources.list.d/ubuntu.sources | grep URIs
# Should show: URIs: http://archive.ubuntu.com/ubuntu
```

## Performance Testing

### Compare Build Times

```bash
# Native amd64 build
time sudo ./build.sh --variant ubuntu-noble --arch amd64

# Cross-compiled arm64 build
time sudo ./build.sh --variant ubuntu-noble --arch arm64

# ARM64 should be 10-50x slower due to QEMU emulation
```

### Resource Usage

```bash
# Monitor CPU and memory during cross-build
sudo ./build.sh --variant ubuntu-noble --arch arm64 &
PID=$!
watch -n 1 "ps aux | grep -E 'PID|$PID|qemu'"
```

## Container Execution Testing

### Run ARM64 Container on x86_64

```bash
# Extract ARM64 image
sudo mkdir -p /var/lib/machines/test-arm64
sudo zstd -d < images/nspawn-ubuntu-noble-arm64.tar.zst | sudo tar -C /var/lib/machines/test-arm64 -xf -

# Run shell in container (QEMU will transparently execute)
sudo systemd-nspawn -D /var/lib/machines/test-arm64 /bin/bash -c 'uname -m'
# Should output: aarch64

# Run command
sudo systemd-nspawn -D /var/lib/machines/test-arm64 /bin/bash -c 'cat /etc/os-release'

# Cleanup
sudo rm -rf /var/lib/machines/test-arm64
```

### Boot Test (Full systemd)

```bash
# Boot the ARM64 container
sudo systemd-nspawn -bD /var/lib/machines/test-arm64

# In another terminal, check it's running
machinectl list
machinectl status test-arm64

# Login and verify
sudo machinectl shell test-arm64 /bin/bash
uname -m  # Should show aarch64
dpkg --print-architecture  # Should show arm64
exit

# Stop the container
sudo machinectl stop test-arm64
```

## CI/CD Testing

### Trigger Workflow Dispatch

```bash
# Test building specific variant/arch via GitHub Actions
gh workflow run build-and-publish.yml \
  -f variant=ubuntu-noble \
  -f arch=arm64 \
  -f image_tag=test-arm64

# Check workflow status
gh run list --workflow=build-and-publish.yml
```

### Download and Test CI Artifacts

```bash
# Download artifact from GitHub Actions
gh run download <run-id> --name nspawn-ubuntu-noble-arm64

# Verify the downloaded image
sudo ./validate.sh --variant ubuntu-noble --arch arm64
```

## Troubleshooting

### Common Issues

#### 1. QEMU Not Found

**Error**: `ERROR: qemu-aarch64-static not found`

**Solution**:
```bash
sudo apt-get install qemu-user-static binfmt-support
```

#### 2. binfmt Not Registered

**Error**: `Exec format error` when running ARM64 binaries

**Solution**:
```bash
sudo systemctl restart binfmt-support
sudo update-binfmts --enable qemu-aarch64
```

#### 3. Wrong Architecture in Image

**Problem**: Built image shows wrong architecture

**Debug**:
```bash
# Check debootstrap command in logs
# Should show: --arch=arm64

# Verify DEBOOTSTRAP_ARCH variable
sudo ./build.sh --variant ubuntu-noble --arch arm64 2>&1 | grep -i arch
```

#### 4. Slow Builds

**Problem**: ARM64 builds taking very long

**Expected**: Cross-architecture builds with QEMU are 10-50x slower than native. This is normal.

**Optimization**:
- Use ARM64 hardware for native builds
- Cache debootstrap downloads
- Build only necessary variants

#### 5. NVIDIA Repository Not Found (ARM64)

**Problem**: NVIDIA variant fails on ARM64

**Debug**:
```bash
# Check if sbsa repository exists
curl -I https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa/
# Should return 200 OK

# Verify architecture detection in script
sudo chroot <rootfs> dpkg --print-architecture
```

## Verification Checklist

Before considering ARM64 support complete:

- [ ] Native amd64 builds work (unchanged)
- [ ] Cross-compiled arm64 builds work
- [ ] Architecture auto-detection works
- [ ] Architecture normalization works (x86_64→amd64, aarch64→arm64)
- [ ] Image naming includes architecture suffix for arm64
- [ ] QEMU static binary copied during build
- [ ] QEMU static binary removed from final image
- [ ] Ubuntu ARM64 uses ports.ubuntu.com mirror
- [ ] Debian ARM64 works with standard mirror
- [ ] NVIDIA variant works on both architectures
- [ ] validate.sh accepts --arch flag
- [ ] tests/run-tests.sh accepts --arch flag
- [ ] CI builds both architectures in matrix
- [ ] Artifacts named correctly (arch suffix)
- [ ] Documentation updated
- [ ] No breaking changes to existing workflows

## Performance Benchmarks

Expected build times on typical GitHub Actions runner:

| Variant | AMD64 (native) | ARM64 (cross) | Slowdown |
|---------|----------------|---------------|----------|
| ubuntu-noble | ~2-3 min | ~15-30 min | ~10x |
| ubuntu-noble-nvidia-560 | ~3-4 min | ~20-40 min | ~10x |

Actual times vary based on:
- Package count
- Customization script complexity
- Network speed (package downloads)
- Runner CPU performance

## Next Steps

After validating ARM64 support:

1. **Merge PR**: Review and merge the feature branch
2. **Tag Release**: Create a release with ARM64 support announcement
3. **Update Docs**: Ensure all documentation reflects multi-arch support
4. **Monitor CI**: Watch for any architecture-specific failures
5. **User Feedback**: Gather feedback on cross-build performance
6. **Consider ARM64 Runners**: Evaluate self-hosted ARM64 runners for faster builds

## References

- [QEMU User Emulation Documentation](https://www.qemu.org/docs/master/user/main.html)
- [Debian Multi-Arch HOWTO](https://wiki.debian.org/Multiarch/HOWTO)
- [Ubuntu Ports](https://wiki.ubuntu.com/ARM/Ubuntu)
- [GitHub Actions ARM64 Runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-larger-runners/about-larger-runners#about-arm64-linux-runners)
