# skl

Install `skl` — the Skillsync CLI — to browse and upload your AI coding
sessions.

## Install

macOS / Linux:

```sh
curl -sSfL https://install.skillsync.com | sh
```

Windows (PowerShell):

```powershell
irm https://install.skillsync.com/install.ps1 | iex
```

### Options

Install a specific version:

```sh
VERSION=0.1.0 curl -sSfL https://install.skillsync.com | sh
```

Install to a custom directory:

```sh
SKL_INSTALL_DIR=/usr/local/bin curl -sSfL https://install.skillsync.com | sh
```

Both work in PowerShell too — set `$env:VERSION` or `$env:SKL_INSTALL_DIR` before running the installer.

## Supported platforms

| OS | Architecture |
|----|-------------|
| Linux | x86_64, aarch64 |
| macOS | x86_64 (Intel), aarch64 (Apple Silicon) |
| Windows | x86_64 |
