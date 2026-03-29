# nspawn-image-builder

Portable, reproducible OCI-based images for `systemd-nspawn`, with S3 export/import.

## Goals

1. Build a minimal Ubuntu-based filesystem tree suitable for `systemd-nspawn`.
2. Allow customization — users list extra packages/scripts in a config file.
3. Pack the tree into a reusable tarball (`.tar.zst`).
4. Upload/download the tarball to/from S3-compatible storage.
5. On a new VM, download + unpack → ready to `systemd-nspawn` boot.

## Design

```
nspawn-image-builder/
├── PLAN.md              # this file
├── config.env           # image knobs (name, base distro, extra pkgs)
├── customize.d/         # drop-in shell scripts run inside the image
│   └── 00-example.sh
├── build.sh             # builds the rootfs tree + packs tarball
├── export.sh            # uploads tarball to S3
├── import.sh            # downloads tarball from S3 + unpacks
├── run.sh               # launches the container via systemd-nspawn
├── validate.sh          # end-to-end validation
└── README.md
```

## Workflow

### Build

```bash
# 1. Edit config.env & drop scripts into customize.d/
# 2. Build image
sudo ./build.sh            # → images/<name>.tar.zst
```

`build.sh` steps:
1. `debootstrap` a minimal Ubuntu rootfs into a temp dir.
2. Bind-mount customize.d into the rootfs.
3. `systemd-nspawn -D <rootfs>` to run each customize script (sorted).
4. Clean apt caches, tmp files.
5. `tar -C <rootfs> -cf - . | zstd -T0 -9 > images/<name>.tar.zst`

### Export (S3)

```bash
./export.sh s3://bucket/path/           # uses awscli or mc
```

### Import + Run (on another VM)

```bash
./import.sh s3://bucket/path/<name>.tar.zst
sudo ./run.sh <name>                    # boots with nspawn
```

### Validate

`validate.sh` checks:
- rootfs tree structure is sane (has /bin, /etc, /usr)
- tarball exists and is extractable
- nspawn can boot the image and run a simple command
- custom packages are installed

## Dependencies

- `debootstrap`, `systemd-container` (for nspawn), `zstd`, `awscli` or `mc`
