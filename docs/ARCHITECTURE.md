# Architecture Support in nspawn-image-builder

## Overview

The nspawn-image-builder supports building systemd-nspawn container images for multiple CPU architectures:

- **amd64** (x86_64) - Intel/AMD 64-bit processors
- **arm64** (aarch64) - ARM 64-bit processors

**ARM64 Support** (added 2026-03-30): Full support for ARM64 architecture has been implemented, enabling builds for ARM-based servers (AWS Graviton, Azure ARM), development workstations (Apple Silicon), and single-board computers (Raspberry Pi, NVIDIA Jetson). The implementation provides both native builds (when host and target architecture match) and cross-architecture builds using QEMU user-mode emulation. Images are automatically named with architecture suffixes (e.g., `nspawn-ubuntu-noble-arm64.tar.zst`) for non-amd64 builds, preserving backward compatibility for existing amd64 workflows.

## Build Modes

### 1. Native Build

Building for the same architecture as the host:

```bash
# On x86_64 host, build for amd64
sudo ./build.sh --variant ubuntu-noble --arch amd64

# On aarch64 host, build for arm64
sudo ./build.sh --variant ubuntu-noble --arch arm64
```

**Characteristics:**
- ✅ Fast (no emulation overhead)
- ✅ Reliable (direct execution)
- ✅ No special prerequisites

### 2. Cross-Architecture Build

Building for a different architecture than the host:

```bash
# On x86_64 host, build for arm64
sudo ./build.sh --variant ubuntu-noble --arch arm64

# On aarch64 host, build for amd64
sudo ./build.sh --variant ubuntu-noble --arch amd64
```

**Characteristics:**
- ⚠️ Slow (~10-50x slower due to QEMU emulation)
- ⚠️ Requires QEMU user-mode emulation
- ✅ Enables building anywhere
- ✅ Useful for CI/CD

**Prerequisites:**
```bash
sudo apt-get install qemu-user-static binfmt-support
```

### 3. Auto-Detection

If `--arch` is not specified, the host architecture is automatically detected:

```bash
# Auto-detects architecture
sudo ./build.sh --variant ubuntu-noble
```

## Architecture Naming

### Input (User-Provided)

The build system accepts multiple naming conventions:

| Debian Style | Kernel Style | Normalized To |
|--------------|--------------|---------------|
| amd64        | x86_64       | amd64         |
| arm64        | aarch64      | arm64         |

### Output (Image Names)

Built images follow this naming convention:

```
<base-name>[-<arch>].tar.zst
```

Where `<arch>` is appended **only for non-amd64 architectures**:

| Variant | Architecture | Image Name |
|---------|--------------|------------|
| ubuntu-noble | amd64 | `nspawn-ubuntu-noble.tar.zst` |
| ubuntu-noble | arm64 | `nspawn-ubuntu-noble-arm64.tar.zst` |
| ubuntu-noble-nvidia-560 | amd64 | `nspawn-ubuntu-noble-nvidia-560.tar.zst` |
| ubuntu-noble-nvidia-560 | arm64 | `nspawn-ubuntu-noble-nvidia-560-arm64.tar.zst` |

This preserves backward compatibility while clearly distinguishing non-default architectures.

## Repository Configuration

### Ubuntu

Ubuntu uses different mirror servers for different architectures:

| Architecture | Mirror | Reason |
|--------------|--------|--------|
| amd64 | `http://archive.ubuntu.com/ubuntu` | Standard mirror |
| arm64 | `http://ports.ubuntu.com/ubuntu-ports` | ARM ports mirror |

The build system automatically selects the correct mirror when using the default Ubuntu configuration.

### Debian

Debian uses unified mirrors for all architectures:

- `http://deb.debian.org/debian` (all architectures)

No special handling needed.

### NVIDIA CUDA

NVIDIA provides architecture-specific repository paths:

| Architecture | Repository Path |
|--------------|----------------|
| amd64 | `ubuntu2404/x86_64` |
| arm64 | `ubuntu2404/sbsa` |

**SBSA** (Server Base System Architecture) is NVIDIA's designation for ARM64 server platforms.

The NVIDIA variant customization script automatically detects the architecture using `dpkg --print-architecture`.

## Technical Implementation

### QEMU User-Mode Emulation

For cross-architecture builds:

1. **Detect Cross-Build**: Compare host architecture (`uname -m`) with target architecture
2. **Validate QEMU**: Check for `qemu-<arch>-static` binary
3. **Copy QEMU**: Copy static binary into rootfs: `/usr/bin/qemu-<arch>-static`
4. **Build**: debootstrap and chroot operations transparently use QEMU via binfmt_misc
5. **Cleanup**: Remove QEMU binary from rootfs before creating tarball

### binfmt_misc

Linux kernel feature that allows executing binaries for foreign architectures:

```bash
# View registered handlers
ls /proc/sys/fs/binfmt_misc/

# Check ARM64 handler
cat /proc/sys/fs/binfmt_misc/qemu-aarch64
```

When enabled, the kernel automatically invokes QEMU when executing ARM64 binaries on x86_64 (and vice versa).

### Debootstrap Integration

```bash
debootstrap --variant=minbase --arch=arm64 noble /path/to/rootfs http://ports.ubuntu.com/ubuntu-ports
```

The `--arch` parameter tells debootstrap to:
- Download packages for the specified architecture
- Configure dpkg for that architecture
- Set up architecture-specific paths

## Architecture Flow

```
User Command:
  ./build.sh --variant ubuntu-noble --arch arm64

         ↓

1. Architecture Normalization
   - Input: "arm64" or "aarch64"
   - Output: "arm64" (Debian convention)

         ↓

2. Cross-Build Detection
   - Host: x86_64 (from uname -m)
   - Target: arm64
   - Cross-build: YES

         ↓

3. QEMU Validation
   - Check: /usr/bin/qemu-aarch64-static exists
   - If missing: Error with installation instructions

         ↓

4. Mirror Selection
   - DISTRO_FAMILY: ubuntu
   - ARCH: arm64
   - BASE_MIRROR: http://ports.ubuntu.com/ubuntu-ports

         ↓

5. Image Name
   - Base: nspawn-ubuntu-noble
   - Arch: arm64 (not amd64)
   - Final: nspawn-ubuntu-noble-arm64

         ↓

6. Debootstrap
   - Command: debootstrap --arch=arm64 noble /tmp/rootfs http://ports.ubuntu.com/ubuntu-ports
   - QEMU copied: /tmp/rootfs/usr/bin/qemu-aarch64-static

         ↓

7. Chroot Operations
   - apt-get install (via QEMU)
   - Customization scripts (via QEMU)
   - All ARM64 binaries transparently executed

         ↓

8. Cleanup
   - Remove: /tmp/rootfs/usr/bin/qemu-aarch64-static
   - Clean apt cache
   - Remove temporary files

         ↓

9. Tarball Creation
   - Compress: tar + zstd
   - Output: images/nspawn-ubuntu-noble-arm64.tar.zst

         ↓

Result:
  Pure ARM64 image (no QEMU, no x86_64 artifacts)
```

## Validation

### Check Built Image Architecture

```bash
# Extract image
mkdir /tmp/test
sudo zstd -d < images/nspawn-ubuntu-noble-arm64.tar.zst | sudo tar -C /tmp/test -xf -

# Check dpkg architecture
sudo chroot /tmp/test dpkg --print-architecture
# Output: arm64

# Check binary format
file /tmp/test/bin/bash
# Output: ELF 64-bit LSB executable, ARM aarch64, ...

# Verify no QEMU
ls /tmp/test/usr/bin/ | grep qemu
# Output: (empty)
```

## CI/CD Architecture Matrix

GitHub Actions builds a matrix of variants × architectures:

```yaml
strategy:
  matrix:
    include:
      - variant: ubuntu-noble
        arch: amd64
      - variant: ubuntu-noble
        arch: arm64
      - variant: ubuntu-noble-nvidia-560
        arch: amd64
      - variant: ubuntu-noble-nvidia-560
        arch: arm64
```

Each combination is built, validated, and tested independently.

## Performance Characteristics

### Native Builds

- **Time**: 2-5 minutes (typical variant)
- **CPU**: 1-2 cores, moderate usage
- **Memory**: 500MB-1GB

### Cross-Architecture Builds (QEMU)

- **Time**: 20-60 minutes (10-50x slower)
- **CPU**: Higher usage due to emulation overhead
- **Memory**: Similar to native
- **Bottleneck**: QEMU translation overhead, not I/O

### Optimization Strategies

1. **Use Native Builds When Possible**
   - ARM64 hardware for ARM64 images
   - x86_64 hardware for x86_64 images

2. **Cache Package Downloads**
   - Set up local apt-cacher-ng
   - Reduces network time (not QEMU time)

3. **Minimize Chroot Operations**
   - Fewer packages = faster builds
   - Optimize customization scripts

4. **Parallel Builds**
   - Build multiple variants simultaneously
   - Use build matrix in CI

## Troubleshooting

### Issue: "qemu-aarch64-static not found"

**Cause**: QEMU user-mode emulation not installed

**Solution**:
```bash
sudo apt-get install qemu-user-static binfmt-support
```

### Issue: "Exec format error" in chroot

**Cause**: binfmt_misc handler not registered

**Solution**:
```bash
sudo systemctl restart binfmt-support
sudo update-binfmts --enable qemu-aarch64
```

### Issue: ARM64 build uses archive.ubuntu.com

**Cause**: Using custom mirror that doesn't auto-switch

**Solution**: Manually set correct mirror in variant config:
```bash
BASE_MIRROR="http://ports.ubuntu.com/ubuntu-ports"
```

### Issue: NVIDIA packages not found on ARM64

**Cause**: Using wrong repository path (x86_64 instead of sbsa)

**Solution**: Ensure customization script uses `dpkg --print-architecture` for dynamic detection

## Future Architecture Support

Potential architectures for future support:

- **armhf** (32-bit ARM) - Older ARM devices
- **riscv64** (RISC-V 64-bit) - Emerging open architecture
- **ppc64el** (PowerPC 64-bit LE) - IBM POWER systems
- **s390x** (IBM Z mainframe) - Enterprise systems

Implementation would follow the same pattern:
1. Add architecture to normalization logic
2. Add debootstrap arch mapping
3. Handle architecture-specific mirrors
4. Update CI matrix
5. Test and document

## Related Documentation

- [ADR-001: ARM64 Support Decision](ADR-001-ARM64-Support.md)
- [ARM64 Testing Guide](ARM64-Testing-Guide.md)
- [README: Multi-Architecture Support](../README.md#multi-architecture-support)

## References

- [Debian Ports](https://www.debian.org/ports/)
- [Ubuntu Ports](https://wiki.ubuntu.com/ARM/Ubuntu)
- [QEMU User Space Emulator](https://www.qemu.org/docs/master/user/main.html)
- [binfmt_misc Documentation](https://www.kernel.org/doc/html/latest/admin-guide/binfmt-misc.html)
- [debootstrap(8) Manual](https://manpages.debian.org/debootstrap)
