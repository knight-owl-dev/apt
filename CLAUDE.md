# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Knight Owl Apt Repository is a Debian/Ubuntu package repository. It uses a hybrid architecture:

- **Cloudflare Pages**: Hosts static metadata files and landing page
- **Cloudflare Functions**: Redirects `.deb` download requests to GitHub Releases
- **GitHub Releases**: Stores actual package binaries (not in this repo)

This design minimizes storage since only apt metadata is stored here, while binaries are served from GitHub.

## Repository Structure

```plain
packages.yml                             # Package configuration (add new packages here)
scripts/update-repo.sh                   # Generate Packages and Release files
scripts/sign-release.sh                  # Sign Release file with GPG
dists/stable/main/binary-{amd64,arm64}/  # Apt package metadata (Packages, Packages.gz)
dists/stable/                            # Release files (Release, InRelease, Release.gpg)
functions/pool/main/<letter>/<package>/  # Cloudflare Functions for binary redirects
tests/                                   # Docker-based installation tests
```

## Commands

### Test Installation

```bash
# Test a package (defaults to first in packages.yml)
./tests/test-package.sh

# Test specific package on specific image
./tests/test-package.sh keystone-cli ubuntu:24.04

# Test all packages
./tests/test-all.sh
```

### Update Repository

```bash
# Run locally (generates unsigned metadata)
./scripts/update-repo.sh

# With specific version
./scripts/update-repo.sh keystone-cli:0.1.9
```

Repository updates are also automated via GitHub Actions (trigger from Actions UI or via `repository_dispatch`).

### Adding a New Package

1. Add entry to `packages.yml`
2. Create Cloudflare Function at `functions/pool/main/<first-letter>/<package>/[[path]].js`
   (copy from existing keystone-cli function and update the repo path)

### Build Landing Page (handled by Cloudflare)

```bash
npx markdown-to-html-cli --source README.md --output index.html
```

## Architecture Details

### Cloudflare Functions (`functions/pool/main/<letter>/<package>/[[path]].js`)

Each package has a function that intercepts `.deb` download requests and returns a 302 redirect to GitHub Releases. This allows apt clients to download binaries without storing them in this repository.

### Apt Metadata Flow

1. Client runs `apt update` → fetches `Release`, `InRelease` from `dists/stable/`
2. Client verifies GPG signature
3. Client fetches `Packages.gz` from `dists/stable/main/binary-{arch}/`
4. Client runs `apt install keystone-cli` → requests `.deb` from `/pool/...`
5. Cloudflare Function redirects to GitHub Releases

### GPG Signing

- Key ID: `25F3 E04A E420 DC2A 0F18 1ADC 89B3 FD22 D208 5FDA`
- Both clearsigned (`InRelease`) and detached (`Release.gpg`) signatures are generated
- Public key available at `/PUBLIC.KEY`
