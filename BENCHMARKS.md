# nspawn-image-builder Benchmarks

> Measured on exe.dev VM (Ubuntu Noble), 2025-03-29

## Image Size

| Metric | Value |
|--------|-------|
| Compressed tarball (`.tar.zst`) | **74 MB** |
| Extracted rootfs | **251 MB** |
| Compression ratio | ~3.4× |

The image includes Ubuntu Noble (minbase) plus: `curl`, `wget`, `vim`, `less`,
`htop`, `net-tools`, `iputils-ping`, `dnsutils`, `ca-certificates`, `systemd`,
`systemd-sysv`, and `dbus`.

## Deploy Speed: Pre-built Image vs From Scratch

| Method | Build / Extract | nspawn Exec | **Total** |
|--------|----------------:|------------:|----------:|
| **From image** (extract `.tar.zst`) | 472 ms | 65 ms | **537 ms** |
| **From scratch** (debootstrap + apt-get) | 87,583 ms | 63 ms | **87,646 ms** |

### Key Takeaway

Deploying from the pre-built image is **~163× faster** than building from
scratch. The container is ready to execute commands in **under 600ms** from a
74 MB download.

## Methodology

### From Image (extract tarball)

```bash
mkdir -p /var/lib/machines/<name>
zstd -d < images/nspawn-base.tar.zst | tar -C /var/lib/machines/<name> -xf -
systemd-nspawn -D /var/lib/machines/<name> --pipe -- /bin/echo hello
```

Timed with nanosecond-precision `date +%s%N`.

### From Scratch (no image)

```bash
debootstrap --variant=minbase noble /var/lib/machines/<name> http://archive.ubuntu.com/ubuntu
chroot /var/lib/machines/<name> apt-get update
chroot /var/lib/machines/<name> apt-get install -y <all packages>
systemd-nspawn -D /var/lib/machines/<name> --pipe -- /bin/echo hello
```

Same timing method. Network download from `archive.ubuntu.com` is included in
the from-scratch time (same data center, fast mirror).

## Breakdown

- **Debootstrap** dominates the from-scratch path (~60s for base, ~27s for
  package install + apt update).
- **zstd decompression + tar extraction** at ~470ms is effectively instant for
  operational purposes.
- **nspawn exec overhead** is ~65ms regardless of how the rootfs was created —
  this is the fixed cost of namespace/cgroup setup.

## Implications for S3 Workflow

| Step | Estimated Time |
|------|---------------:|
| S3 download (74 MB @ 1 Gbps) | ~600 ms |
| Extract tarball | ~470 ms |
| nspawn ready | ~65 ms |
| **Total cold-start from S3** | **~1.1 s** |

Compare to ~88s for a from-scratch build. Pre-built images make sub-2-second
container provisioning realistic across VMs.
