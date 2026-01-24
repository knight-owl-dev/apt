# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Knight Owl Apt Repository is a Debian/Ubuntu package repository for distributing `keystone-cli`. It uses a hybrid architecture:

- **Cloudflare Pages**: Hosts static metadata files and landing page
- **Cloudflare Functions**: Redirects `.deb` download requests to GitHub Releases
- **GitHub Releases**: Stores actual package binaries (not in this repo)

This design minimizes storage since only apt metadata is stored here, while binaries are served from GitHub.

## Repository Structure

```plain
dists/stable/main/binary-{amd64,arm64}/  # Apt package metadata (Packages, Packages.gz)
dists/stable/                            # Release files (Release, InRelease, Release.gpg)
functions/pool/main/k/keystone-cli/      # Cloudflare Function for binary redirects
docs/how-to/                             # Workflow documentation
tests/                                   # Docker-based installation tests
```

## Commands

### Test Installation

```bash
# Test on Debian (default)
./tests/test-keystone-cli.sh

# Test on specific distribution
./tests/test-keystone-cli.sh ubuntu:24.04
```

### Update Repository

Repository updates are automated via GitHub Actions. Trigger manually from the Actions UI or via `repository_dispatch`.

The workflow:

1. Downloads `.deb` packages from keystone-cli releases
2. Generates `Packages` and `Release` files
3. Signs with GPG (requires `GPG_PRIVATE_KEY` and `GPG_PASSPHRASE` secrets)
4. Commits and pushes to `main`

### Build Landing Page (handled by Cloudflare)

```bash
npx markdown-to-html-cli --source README.md --output index.html
```

## Architecture Details

### Cloudflare Function (`functions/pool/main/k/keystone-cli/[[path]].js`)

Intercepts requests like `/pool/main/k/keystone-cli/keystone-cli_0.1.9_amd64.deb` and returns a 302 redirect to GitHub Releases. This allows apt clients to download binaries without storing them in this repository.

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
