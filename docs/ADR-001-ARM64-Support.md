# ADR-001: ARM64 Architecture Support

## Status

Accepted (2026-03-30)

## Context

The nspawn-image-builder project initially supported only x86_64/amd64 architecture. Users requested support for ARM64/aarch64 to enable:

1. Building images for ARM-based servers (AWS Graviton, Azure ARM, Oracle Ampere)
2. Development on ARM-based workstations (Apple M1/M2/M3, ARM Linux laptops)
3. Deployment on Single Board Computers (Raspberry Pi, NVIDIA Jetson)
4. Testing and validation across multiple architectures

## Decision

We decided to implement **hybrid architecture support** that allows:

1. **Native builds**: When host and target architecture match
2. **Cross-architecture builds**: Using QEMU user-mode emulation for foreign architectures
3. **Automatic detection**: Host architecture is auto-detected if not explicitly specified
4. **Explicit control**: Users can override with `--arch` flag

### Architecture Naming

We normalize architecture names to Debian conventions:
- `amd64` (also accepts `x86_64`)
- `arm64` (also accepts `aarch64`)

This aligns with debootstrap, dpkg, and other Debian/Ubuntu tooling.

### Image Naming Convention

To avoid breaking existing workflows:
- **Default (amd64)**: No suffix → `nspawn-ubuntu-noble.tar.zst`
- **Non-default**: Architecture suffix → `nspawn-ubuntu-noble-arm64.tar.zst`

This preserves backward compatibility while clearly distinguishing non-amd64 images.

### Cross-Architecture Approach

We chose QEMU user-mode emulation over:
1. **Native-only builds**: Too restrictive, requires ARM64 build infrastructure
2. **Container-based emulation**: Added complexity, similar performance to QEMU
3. **Full system emulation**: Too slow, unnecessary overhead

QEMU user-static provides:
- ✅ Transparent execution of foreign binaries via binfmt_misc
- ✅ Works within chroot environments (debootstrap, apt)
- ✅ Available in standard repos (`qemu-user-static`)
- ✅ Well-tested and widely used in cross-compilation workflows
- ⚠️ Performance penalty (~10-50x slower than native)

### Repository Handling

#### Ubuntu
- **amd64**: Use standard `archive.ubuntu.com`
- **arm64**: Auto-switch to `ports.ubuntu.com/ubuntu-ports`

This is handled automatically in build.sh when the default mirror is detected.

#### Debian
- Both architectures use the same mirror (`deb.debian.org`)
- Architecture selection via debootstrap `--arch` flag

#### NVIDIA Repositories
- **amd64**: Use `x86_64` path
- **arm64**: Use `sbsa` path (Server Base System Architecture)

Detected dynamically in customization scripts using `dpkg --print-architecture`.

## Consequences

### Positive

1. **Flexibility**: Users can build for any supported architecture from any supported host
2. **CI/CD Integration**: GitHub Actions can build both architectures in parallel
3. **Zero Breaking Changes**: Existing workflows continue to work unchanged
4. **Clear Documentation**: Architecture is explicit in image names and logs
5. **Maintainable**: Architecture logic centralized in build.sh

### Negative

1. **Build Time**: Cross-architecture builds are significantly slower (QEMU overhead)
2. **CI Cost**: Doubled build matrix (2 architectures × N variants)
3. **Complexity**: More code paths, more testing surface
4. **QEMU Dependency**: Cross-builds require additional packages

### Mitigation Strategies

1. **Slow Builds**: Document performance expectations, consider ARM64 self-hosted runners in future
2. **CI Cost**: Use workflow dispatch to build specific architectures on-demand
3. **Complexity**: Comprehensive tests, clear error messages, good documentation
4. **QEMU Dependency**: Clear prerequisite documentation, validation checks in build.sh

## Alternatives Considered

### 1. Native-Only Builds

**Rejected**: Too restrictive. Would require users to have ARM64 hardware or pay for ARM64 CI runners.

### 2. Separate Variants for Each Architecture

**Rejected**: Would create `ubuntu-noble-amd64.conf` and `ubuntu-noble-arm64.conf`. This:
- Doubles variant files
- Duplicates configuration
- Makes multi-arch less discoverable

Our approach (single variant + `--arch` flag) is more maintainable.

### 3. Architecture in Image Name Always

**Rejected**: Would break backward compatibility. `nspawn-ubuntu-noble.tar.zst` → `nspawn-ubuntu-noble-amd64.tar.zst`.

Our approach (suffix only for non-default) preserves existing names.

### 4. Docker Buildx / BuildKit

**Rejected**: Would require containerizing the build process. Added complexity, different execution model (systemd-nspawn vs Docker).

Our approach keeps the build process simple and direct.

## Implementation Notes

### QEMU Static Binary Handling

1. **Copy**: QEMU binary copied into rootfs for chroot operations
2. **Use**: Transparent execution via binfmt_misc kernel support
3. **Cleanup**: QEMU binary removed before tarball creation

This ensures:
- ✅ Chroot commands work (apt, systemd, custom scripts)
- ✅ Final image doesn't include QEMU (not needed at runtime)
- ✅ Image size unchanged

### Architecture Detection Flow

```
1. User specifies --arch OR auto-detect with uname -m
2. Normalize to Debian convention (amd64/arm64)
3. Check if cross-build needed (host != target)
4. Validate QEMU available for cross-builds
5. Set DEBOOTSTRAP_ARCH for package manager
6. Append suffix to IMAGE_NAME if not amd64
7. Pass architecture to debootstrap --arch
```

### Testing Strategy

- Unit tests: Architecture normalization logic
- Integration tests: Full build + validation for both architectures
- CI tests: Matrix builds all variants × all architectures
- Cross-build validation: Verify QEMU integration works

## Future Improvements

1. **ARM64 Self-Hosted Runners**: Speed up native ARM64 builds in CI
2. **Build Caching**: Cache debootstrap downloads, QEMU setup
3. **More Architectures**: armhf (32-bit ARM), riscv64, ppc64el
4. **Parallel Builds**: Build multiple variants in parallel locally
5. **OCI Multi-Arch**: Combine amd64 + arm64 into single OCI manifest

## References

- Issue #9: Implement ARM64 support
- PR #10: Implementation of this ADR
- [Debian Multi-Arch](https://wiki.debian.org/Multiarch)
- [QEMU User Emulation](https://www.qemu.org/docs/master/user/main.html)
- [GitHub Actions ARM64](https://github.blog/changelog/2024-06-03-actions-arm-based-linux-and-windows-runners-are-now-in-public-beta/)
