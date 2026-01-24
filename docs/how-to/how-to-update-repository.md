# How to Update the Repository

This guide explains how apt metadata is generated and published when a new package version is released.

## Overview

The apt repository stores only metadata. Binary packages (`.deb` files) are served directly from
GitHub Releases via Cloudflare Functions that redirect based on package version.

## Architecture

```plain
┌─────────────────────────────────────────────────────────────────────────────┐
│                              apt.knight-owl.dev                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  Cloudflare Pages (static)          │  Cloudflare Functions (dynamic)       │
│  ─────────────────────────────────  │  ──────────────────────────────────   │
│  /PUBLIC.KEY                        │  /pool/main/k/keystone-cli/*.deb      │
│  /dists/stable/Release              │    → parses version from filename     │
│  /dists/stable/InRelease            │    → redirects to GitHub Releases     │
│  /dists/stable/main/binary-*/       │                                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
                              GitHub Releases (binary storage)
                              github.com/knight-owl-dev/keystone-cli/releases
```

## Triggering the Workflow

### Manual trigger

1. Go to GitHub Actions → **Update Repository**
2. Click **Run workflow**
3. Optionally enter a version (e.g., `0.1.9`), or leave empty for latest

### Automated trigger (planned)

The keystone-cli release workflow will trigger this via `repository_dispatch` after publishing
a new release.

## Workflow Steps

### 1. Determine version

The workflow resolves the version from (in order):

1. Manual input (`workflow_dispatch`)
2. Dispatch payload (`repository_dispatch`)
3. Latest release from keystone-cli

### 2. Download .deb packages

Downloads both architectures from GitHub Releases:

```plain
https://github.com/knight-owl-dev/keystone-cli/releases/download/v{VERSION}/keystone-cli_{VERSION}_amd64.deb
https://github.com/knight-owl-dev/keystone-cli/releases/download/v{VERSION}/keystone-cli_{VERSION}_arm64.deb
```

These are temporary — used only to extract metadata.

### 3. Generate Packages files

For each architecture, the workflow:

1. Extracts control metadata from the `.deb` using `dpkg-deb -f`
2. Computes checksums (MD5, SHA1, SHA256)
3. Writes `Packages` and `Packages.gz` to `dists/stable/main/binary-{arch}/`

### 4. Generate Release file

Creates `dists/stable/Release` containing:

- Repository metadata (Origin, Label, Suite, Codename, Architectures, Components)
- Checksums of all `Packages` and `Packages.gz` files

### 5. Sign with GPG

Using the GPG key stored in repository secrets:

- `InRelease` — clearsigned Release (inline signature)
- `Release.gpg` — detached armored signature

### 6. Commit and push

Commits all generated files to the `main` branch. Cloudflare Pages automatically redeploys
on push.

## Generated Files

| File                                         | Purpose                            |
|----------------------------------------------|------------------------------------|
| `dists/stable/main/binary-amd64/Packages`    | Package metadata for amd64         |
| `dists/stable/main/binary-amd64/Packages.gz` | Compressed package metadata        |
| `dists/stable/main/binary-arm64/Packages`    | Package metadata for arm64         |
| `dists/stable/main/binary-arm64/Packages.gz` | Compressed package metadata        |
| `dists/stable/Release`                       | Repository metadata with checksums |
| `dists/stable/InRelease`                     | GPG clearsigned Release            |
| `dists/stable/Release.gpg`                   | GPG detached signature             |

## User Install Flow

```bash
# 1. apt-get update fetches metadata from Cloudflare Pages
apt-get update
  → GET https://apt.knight-owl.dev/dists/stable/InRelease
  → GET https://apt.knight-owl.dev/dists/stable/main/binary-amd64/Packages.gz

# 2. apt-get install requests the .deb from pool path
apt-get install keystone-cli
  → GET https://apt.knight-owl.dev/pool/main/k/keystone-cli/keystone-cli_0.1.9_amd64.deb
  → Cloudflare Function returns 302 redirect
  → GET https://github.com/knight-owl-dev/keystone-cli/releases/download/v0.1.9/keystone-cli_0.1.9_amd64.deb
```

## Secrets Required

| Secret            | Purpose                         |
|-------------------|---------------------------------|
| `GPG_PRIVATE_KEY` | Armored private key for signing |
| `GPG_PASSPHRASE`  | Passphrase for the GPG key.     |

## Troubleshooting

### Workflow fails to download .deb

Verify the release exists and contains the expected `.deb` files:

```bash
gh release view v{VERSION} --repo knight-owl-dev/keystone-cli
```

### GPG signing fails

Check that secrets are configured correctly:

```bash
gh secret list --repo knight-owl-dev/apt
```

### Metadata not updating on apt.knight-owl.dev

Cloudflare Pages should auto-deploy on push. Check the deployment status in the
Cloudflare dashboard.
