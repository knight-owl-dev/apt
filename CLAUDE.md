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
scripts/lib/                             # Shared shell libraries (validation, checksums, require)
dists/stable/main/binary-{amd64,arm64}/  # Apt package metadata (Packages, Packages.gz)
dists/stable/                            # Release files (Release, InRelease, Release.gpg)
functions/_middleware.js                 # Access control (blocks dev files from public)
functions/pool/main/<letter>/<package>/  # Cloudflare Functions for binary redirects
tests/                                   # Docker-based installation tests
```

## Commands

Run `make help` to see all available commands. Examples:

```bash
make test                                # Test all packages
make test PKG=keystone-cli               # Test specific package
make test IMAGE=ubuntu:24.04             # Test on specific image
make validate                            # Validate local repo generation
make update                              # Update all packages to latest
make update VERSIONS=keystone-cli:0.1.9  # Update specific version
```

Or use the scripts directly:

```bash
./tests/test-package.sh keystone-cli ubuntu:24.04
./tests/test-all.sh
./scripts/update-repo.sh keystone-cli:0.1.9
```

Repository updates are also automated via GitHub Actions (trigger from Actions UI or via `repository_dispatch`).

> **Note:** The `update-repo.yml` workflow creates PRs with auto-merge enabled. PRs are
> automatically squash-merged after CI passes.

### Adding a New Package

1. Add entry to `packages.yml`
2. Create Cloudflare Function at `functions/pool/main/<letter>/<package>/[[path]].js`
   (copy from existing keystone-cli function and update the repo path)

See [docs/how-to/how-to-add-a-new-package.md](docs/how-to/how-to-add-a-new-package.md) for detailed steps.

### Shell Script Quality

Shell scripts are checked by [shfmt](https://github.com/mvdan/sh) (formatting) and
[ShellCheck](https://github.com/koalaman/shellcheck) (linting). CI enforces both.

```bash
make lint        # Check formatting (shfmt) + linting (shellcheck)
make lint-fix    # Auto-fix formatting
```

**shfmt flags:**

| Flag   | Meaning                              |
| ------ | ------------------------------------ |
| `-i 2` | 2-space indentation                  |
| `-ci`  | Indent case labels                   |
| `-bn`  | Binary ops (`&&`, `\|`) start a line |
| `-sr`  | Redirect operators followed by space |

**ShellCheck configuration (`.shellcheckrc`):**

| Option                       | Meaning                                    |
| ---------------------------- | ------------------------------------------ |
| `shell=bash`                 | Assume bash dialect                        |
| `external-sources=true`      | Follow sourced files                       |
| `require-variable-braces`    | Require `${var}` instead of `$var`         |
| `quote-safe-variables`       | Warn on unquoted variables                 |
| `check-unassigned-uppercase` | Warn on uninitialized uppercase vars       |
| `check-extra-masked-returns` | Detect hidden exit codes                   |
| `require-double-brackets`    | Enforce `[[` over `[` for bash             |
| `deprecate-which`            | Use `command -v` instead of `which`        |

### Workflow Script Style

Inline shell scripts in GitHub Actions workflows can't be auto-linted. Follow these guidelines:

- Use `${VAR}` for variable references (consistent with shellcheck `require-variable-braces`)
- Use `[[ ]]` for tests (consistent with shellcheck `require-double-brackets`)
- Keep inline scripts minimal - extract complex logic (>10 lines) to scripts in `scripts/`
- When disabling shellcheck rules, include a reason: `# shellcheck disable=SC2086 -- reason here`

### Build Landing Page (handled by Cloudflare)

```bash
npx markdown-to-html-cli --source README.md --output index.html
```

## Architecture Details

### Cloudflare Functions

**Middleware** (`functions/_middleware.js`): Blocks access to development files (scripts, tests, docs, config). Only allows apt-required routes: `/`, `/PUBLIC.KEY`, `/dists/*`, `/pool/*`.

**Package redirects** (`functions/pool/main/<letter>/<package>/[[path]].js`): Each package has a function that intercepts `.deb` download requests and returns a 302 redirect to GitHub Releases. This allows apt clients to download binaries without storing them in this repository.

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

## Security

For detailed security guidelines, see [docs/how-to/how-to-security.md](docs/how-to/how-to-security.md).

### Access Control

The middleware (`functions/_middleware.js`) restricts public access to apt-required paths only:

| Allowed           | Blocked                                      |
| ----------------- | -------------------------------------------- |
| `/`, `/index.html`| `/scripts/*`, `/tests/*`, `/docs/*`          |
| `/PUBLIC.KEY`     | `/.github/*`, `/CLAUDE.md`, `/packages.yml`  |
| `/dists/*`        | `/Makefile`, `/_redirects`, etc.             |
| `/pool/*`         |                                              |

### Input Validation

All user inputs are validated at multiple layers:

| Input               | Validation                                           | Location                    |
| ------------------- | ---------------------------------------------------- | --------------------------- |
| Package name        | `^[a-z0-9]+(-[a-z0-9]+)*$`                           | `scripts/lib/validation.sh` |
| Version             | `^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$` (semver) | `scripts/lib/validation.sh` |
| Cloudflare redirect | Semver regex per package                             | `functions/pool/main/...`   |

### Checksum Verification

Downloaded `.deb` files are verified against SHA256 checksums:

- Releases **must** include a `SHA256SUMS` file (or `SHA256SUMS.txt`, `checksums.txt`, `checksums-sha256.txt`)
- Downloads fail if checksums file is missing or checksum doesn't match
- Protects against MITM attacks and download corruption

### Shared Libraries

Common functions are in `scripts/lib/`:

| Library         | Purpose                                              |
| --------------- | ---------------------------------------------------- |
| `validation.sh` | Input validation (package names, versions)           |
| `checksums.sh`  | Cross-platform checksums (MD5, SHA1, SHA256, size)   |
| `require.sh`    | Dependency checks (bash4, yq, gh, docker, dpkg)      |
| `packages.sh`   | Debian Packages file parsing (version, block)        |

```bash
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/checksums.sh"
source "$SCRIPT_DIR/lib/require.sh"

require_bash4 || exit 1
require_yq || exit 1
validate_package_name "my-package" || exit 1
```
