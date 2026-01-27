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
│  /PUBLIC.KEY                        │  /pool/main/<letter>/<package>/*.deb  │
│  /dists/stable/Release              │    → parses version from filename     │
│  /dists/stable/InRelease            │    → redirects to GitHub Releases     │
│  /dists/stable/main/binary-*/       │                                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
                              GitHub Releases (binary storage)
                              github.com/knight-owl-dev/<package>/releases
```

## Configuration

All packages are configured in `packages.yml`:

```yaml
packages:
  - name: keystone-cli
    repo: knight-owl-dev/keystone-cli
    architectures:
      - amd64
      - arm64
    verify: keystone-cli info
```

## Running Locally

Generate unsigned metadata locally using the update script:

```bash
# All packages, latest versions
./scripts/update-repo.sh

# Single package, latest version
./scripts/update-repo.sh keystone-cli

# Single package, specific version
./scripts/update-repo.sh keystone-cli:0.1.9

# Multiple packages
./scripts/update-repo.sh keystone-cli:0.1.9 other-package:1.0.0
```

Requirements: Bash 4+, `yq`, `gh` CLI, `dpkg-deb`, `curl`

> **Note:** Local runs generate unsigned metadata for testing only. Do not commit these
> files — the GitHub Actions workflow generates and signs the official metadata. Discard
> local changes with `git restore dists/` before committing.

## Triggering the Workflow

### Manual trigger

1. Go to GitHub Actions → **Update Repository**
2. Click **Run workflow**
3. Optionally specify packages:
   - Empty → all packages, latest versions
   - `keystone-cli` → single package, latest version
   - `keystone-cli:0.1.9` → single package, specific version

### Automated trigger

Package release workflows can trigger this via `repository_dispatch`. Add this step to your
release workflow:

```yaml
- name: Trigger apt repository update
  uses: peter-evans/repository-dispatch@v4
  with:
    token: ${{ secrets.APT_REPO_TOKEN }}
    repository: knight-owl-dev/apt
    event-type: release-published
    client-payload: '{"versions": "my-package:${{ needs.release.outputs.version }}"}'
```

Required setup:

1. Create a fine-grained PAT scoped to `knight-owl-dev/apt` with **Contents: Read and write**
2. Add the PAT as a secret (e.g., `APT_REPO_TOKEN`) in your package's repository

You can also trigger manually via the `gh` CLI:

```bash
gh api repos/knight-owl-dev/apt/dispatches \
  -f event_type=release-published \
  -f client_payload='{"versions": "keystone-cli:0.1.9"}'
```

## Workflow Steps

### 1. Determine versions

The workflow resolves versions from (in order):

1. Manual input (`workflow_dispatch`)
2. Dispatch payload (`repository_dispatch`)
3. Latest release from each package's GitHub repo

### 2. Run update-repo.sh

The script (`scripts/update-repo.sh`):

1. Validates package names and versions (semver format required)
2. Reads package configuration from `packages.yml`
3. Downloads `SHA256SUMS` file from each GitHub Release
4. Downloads `.deb` files and verifies checksums (fails if mismatch)
5. Extracts control metadata using `dpkg-deb -f`
6. Computes checksums (MD5, SHA1, SHA256)
7. Generates `Packages` and `Packages.gz` for each architecture
8. Generates `Release` file with repository metadata

### 3. Sign with GPG

The signing script (`scripts/sign-release.sh`) creates:

- `InRelease` — clearsigned Release (inline signature)
- `Release.gpg` — detached armored signature

### 4. Create PR and auto-merge

Creates a PR with the generated files and enables auto-merge (squash). After CI passes,
the PR is automatically merged to `main`. Cloudflare Pages automatically redeploys on merge.

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

| Secret            | Purpose                                      |
|-------------------|----------------------------------------------|
| `GPG_PRIVATE_KEY` | Armored private key for signing              |
| `GPG_PASSPHRASE`  | Passphrase for the GPG key                   |
| `PR_TOKEN`        | Fine-grained PAT for creating PRs (see below)|

### PR_TOKEN Setup

The workflow uses a fine-grained Personal Access Token to create PRs. This is required because
`GITHUB_TOKEN` doesn't trigger other workflows, so CI wouldn't run on auto-created PRs.

**Create the token:**

1. Go to https://github.com/settings/personal-access-tokens/new
2. Name: `apt-pr-token`
3. Expiration: 90 days (or your preference)
4. Repository access: Select `knight-owl-dev/apt` only
5. Permissions:
   - **Contents**: Read and write
   - **Pull requests**: Read and write
6. Generate token

**Set the secret:**

```bash
gh secret set PR_TOKEN --repo knight-owl-dev/apt
# Paste the token when prompted
```

**Regenerate an expired token:**

1. Go to https://github.com/settings/personal-access-tokens/active
2. Click on the token → **Regenerate token**
3. Update the secret:

```bash
gh secret set PR_TOKEN --repo knight-owl-dev/apt
```

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

### yq not found

Install `yq` on macOS:

```bash
brew install yq
```

Install `yq` on Linux:

```bash
sudo snap install yq
```
