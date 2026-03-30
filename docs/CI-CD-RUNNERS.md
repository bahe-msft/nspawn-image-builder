# CI/CD Runner Configuration

This document explains how to configure GitHub Actions runners for multi-architecture builds.

## Overview

The `build-and-publish.yml` workflow supports building images for both AMD64 and ARM64 architectures. To achieve optimal performance, the workflow uses:

- **AMD64 builds**: GitHub-hosted `ubuntu-latest` runners (x86_64)
- **ARM64 builds**: Self-hosted ARM64 runners with labels `[self-hosted, linux, ARM64]`

## ARM64 Runner Setup

### Option 1: Self-Hosted ARM64 Runners (Recommended)

For best performance, configure self-hosted ARM64 runners with the following labels:

```yaml
labels:
  - self-hosted
  - linux  
  - ARM64
```

#### Setting Up a Self-Hosted ARM64 Runner

1. **Provision an ARM64 machine**
   - Physical ARM64 hardware (e.g., Raspberry Pi 4/5, NVIDIA Jetson, ARM server)
   - Cloud ARM64 instance (AWS Graviton, Azure Dpsv5, GCP Tau T2A)
   - Minimum: 4GB RAM, 20GB disk space

2. **Install runner software**
   ```bash
   # Download runner (replace VERSION with latest from GitHub)
   mkdir actions-runner && cd actions-runner
   curl -o actions-runner-linux-arm64-VERSION.tar.gz -L \
     https://github.com/actions/runner/releases/download/vVERSION/actions-runner-linux-arm64-VERSION.tar.gz
   tar xzf ./actions-runner-linux-arm64-VERSION.tar.gz
   
   # Configure runner
   ./config.sh --url https://github.com/YOUR-ORG/nspawn-image-builder \
     --token YOUR-REGISTRATION-TOKEN \
     --labels self-hosted,linux,ARM64
   
   # Install as service
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

3. **Verify runner registration**
   - Go to `Settings > Actions > Runners` in your repository
   - Confirm runner appears with labels: `self-hosted`, `linux`, `ARM64`

### Option 2: GitHub-Hosted ARM64 Runners

GitHub offers ARM64 hosted runners for **Team** and **Enterprise** plans:

```yaml
runs-on: ubuntu-24.04-arm64  # or ubuntu-22.04-arm64
```

To use GitHub-hosted ARM64 runners, modify `.github/workflows/build-and-publish.yml`:

```yaml
runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm64' || 'ubuntu-latest' }}
```

**Note**: GitHub-hosted ARM64 runners are NOT available for free/public repositories.

### Option 3: QEMU Cross-Compilation (Fallback)

If ARM64 runners are unavailable, you can use QEMU cross-compilation on x86_64 runners:

1. **Modify `.github/workflows/build-and-publish.yml`**:
   ```yaml
   runs-on: ubuntu-latest  # For both AMD64 and ARM64
   ```

2. **Remove conditional QEMU setup**:
   Change:
   ```yaml
   if: steps.detect.outputs.need_qemu == 'true'
   ```
   To:
   ```yaml
   if: matrix.arch == 'arm64'
   ```

⚠️ **Warning**: Cross-compilation is 10-50x slower than native builds.

## Runner Requirements

### ARM64 Runner Specifications

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 20 GB | 50+ GB |
| OS | Ubuntu 20.04+ | Ubuntu 24.04 |

### Required Software

Self-hosted runners need:

```bash
# System packages
sudo apt-get update
sudo apt-get install -y \
  debootstrap \
  systemd-container \
  zstd \
  docker.io \
  git

# Docker permissions
sudo usermod -aG docker $USER
```

## Troubleshooting

### ARM64 Jobs Not Starting

**Symptom**: ARM64 jobs remain in "Queued" status indefinitely

**Causes**:
1. No ARM64 runners registered
2. Runner labels don't match `[self-hosted, linux, ARM64]`
3. Runner is offline/unavailable

**Solutions**:
- Verify runner is online: `Settings > Actions > Runners`
- Check runner labels match exactly (case-sensitive)
- Review runner logs: `journalctl -u actions.runner.*`

### Build Failures on ARM64 Runners

**Symptom**: Builds fail with architecture mismatches

**Solutions**:
1. Verify runner architecture:
   ```bash
   uname -m  # Should output: aarch64
   ```

2. Check Docker architecture:
   ```bash
   docker info | grep Architecture  # Should show: aarch64
   ```

### Performance Issues

**Symptom**: ARM64 builds are unexpectedly slow

**Causes**:
- Running on QEMU (cross-compilation)
- Insufficient resources

**Check if using QEMU**:
```bash
# In workflow logs, look for:
"Needs QEMU: true"  # Bad - cross-compiling
"Needs QEMU: false" # Good - native build
```

## Monitoring

### Check Runner Status

```bash
# Via GitHub CLI
gh api repos/YOUR-ORG/nspawn-image-builder/actions/runners

# Via web UI
https://github.com/YOUR-ORG/nspawn-image-builder/settings/actions/runners
```

### View Build Logs

Workflow logs show architecture information:

```
Detect runner architecture:
  Runner architecture: aarch64
  Target architecture: arm64
  Needs QEMU: false
```

## Cost Comparison

| Option | Cost | Speed | Complexity |
|--------|------|-------|------------|
| Self-hosted ARM64 | Hardware/Cloud cost | 1x (native) | Medium |
| GitHub ARM64 | ~$0.16/min | 1x (native) | Low |
| QEMU on x86_64 | Included (free) | 0.02-0.1x | Low |

## Recommendations

1. **Production**: Use self-hosted ARM64 runners or GitHub ARM64 runners
2. **Development/Testing**: QEMU cross-compilation is acceptable
3. **Hybrid**: Use ARM64 runners for main branch, QEMU for PRs

## Security Considerations

### Self-Hosted Runners

⚠️ **WARNING**: Self-hosted runners should NOT be used for public repositories with untrusted contributors.

**Best practices**:
- Use ephemeral runners (destroy after each job)
- Run in isolated environments (VMs/containers)
- Limit runner access to specific repositories
- Regular security updates

### GitHub-Hosted Runners

✅ **Recommended** for public repositories - fully isolated and ephemeral.

## Additional Resources

- [GitHub Actions: About self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners)
- [GitHub Actions: ARM64 runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources)
- [QEMU User Mode Documentation](https://www.qemu.org/docs/master/user/main.html)
