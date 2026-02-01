# Security: Workflows and Scripts

This guide documents the security patterns implemented in this repository for GitHub Actions
workflows and shell scripts.

## GitHub Actions Security

### Script Injection Prevention

GitHub Actions workflows are vulnerable to script injection when untrusted inputs (like PR titles,
branch names, or workflow inputs) are interpolated directly into shell commands. This repository
prevents injection by passing untrusted inputs through environment variables.

**Safe pattern (used in `update-repo.yml`):**

```yaml
- name: Build version arguments
  env:
    # Pass untrusted inputs via env vars to prevent script injection
    INPUT_VERSIONS: ${{ inputs.versions }}
    PAYLOAD_VERSIONS: ${{ github.event.client_payload.versions }}
  run: |
    if [[ -n "${INPUT_VERSIONS}" ]]; then
      echo "versions=${INPUT_VERSIONS}" >> "${GITHUB_OUTPUT}"
    fi
```

**Unsafe pattern (never do this):**

```yaml
# DANGEROUS: Direct interpolation allows injection
run: |
  echo "Processing ${{ inputs.versions }}"
```

With the safe pattern, even if an attacker supplies a malicious input like `; rm -rf /`, the value
is treated as a literal string rather than being executed as code.

### Least-Privilege Permissions

Workflows use minimal permissions by default:

1. **Disable persist-credentials**:

   ```yaml
   - uses: actions/checkout@v6
     with:
       persist-credentials: false
   ```

   This prevents the automatic `GITHUB_TOKEN` from persisting in the git config, reducing the risk
   of token leakage in subsequent steps.

2. **Token scoping**: The workflow uses two tokens with different scopes:
   - `github.token`: Read-only access for fetching releases
   - `PR_TOKEN` (secret): Write access only for creating PRs

### Concurrency Control

The workflow uses concurrency settings to prevent race conditions:

```yaml
concurrency:
  group: update-repo
  cancel-in-progress: false
```

This ensures only one update runs at a time, preventing conflicting commits or partial updates.

## Shell Script Security

### Strict Mode

All shell scripts begin with strict mode:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Flag          | Effect                                           |
|---------------|--------------------------------------------------|
| `-e`          | Exit immediately on command failure              |
| `-u`          | Error on undefined variables                     |
| `-o pipefail` | Propagate errors through pipes                   |

Scripts using strict mode:

- `scripts/update-repo.sh`
- `scripts/sign-release.sh`
- `scripts/create-update-pr.sh`
- `scripts/lib/*.sh`
- `tests/*.sh`

### Input Validation

All user inputs are validated before use. The validation functions in `scripts/lib/validation.sh`
use strict regex patterns:

**Package names**:

```bash
# Only lowercase alphanumeric with hyphens
[[ "${name}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
```

**Versions**:

```bash
# Semver format: X.Y.Z or X.Y.Z-prerelease
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]
```

Usage in scripts:

```bash
source "${SCRIPT_DIR}/lib/validation.sh"

validate_package_name "${package}" || exit 1
validate_version "${version}" || exit 1
```

### Safe Variable Quoting

ShellCheck enforces `require-variable-braces`, requiring `${VAR}` syntax instead of `$VAR`.
This prevents ambiguity and accidental concatenation issues:

```bash
# Good: Clear variable boundaries
echo "Package: ${package}_${version}_${arch}.deb"

# Bad: Ambiguous - is it $package_ or $package?
echo "Package: $package_$version_$arch.deb"
```

### Path Traversal Protection

The repository validates filesystem paths to prevent symlink-based attacks:

```bash
# Ensure artifacts directory is safe (no symlink path traversal)
if [[ -L "${ARTIFACTS_DIR}" ]]; then
  echo "Error: ${ARTIFACTS_DIR} is a symlink, refusing to continue"
  exit 1
fi
mkdir -p "${ARTIFACTS_DIR}"

# Verify resolved path stays within repository
REAL_ARTIFACTS="$(realpath "${ARTIFACTS_DIR}")"
REAL_REPO="$(realpath "${REPO_ROOT}")"
if [[ "${REAL_ARTIFACTS}" != "${REAL_REPO}/artifacts" ]]; then
  echo "Error: Artifacts directory resolves outside repository: ${REAL_ARTIFACTS}"
  exit 1
fi
```

This prevents an attacker from:

1. Creating a symlink at `artifacts/` pointing outside the repository
2. Using path traversal (`../`) to write files to arbitrary locations

### Checksum Verification

All downloaded `.deb` files are verified against SHA256 checksums. The `scripts/lib/checksums.sh`
library provides cross-platform checksum functions.

Requirements:

- Releases **must** include a checksums file (`SHA256SUMS`, `SHA256SUMS.txt`, `checksums.txt`,
  or `checksums-sha256.txt`)
- Downloads fail if the checksums file is missing
- Downloads fail if the checksum doesn't match

This protects against:

- Man-in-the-middle attacks during download
- Corrupted downloads
- Compromised upstream releases (when combined with GPG verification)

## Cloudflare Access Control

The middleware (`functions/_middleware.js`) implements a whitelist-based access control:

```javascript
// Allowed exact paths
const allowedExact = ['/', '/index.html', '/PUBLIC.KEY'];

// Allowed path prefixes (apt routes)
const allowedPrefixes = ['/dists', '/pool/'];
```

| Allowed            | Blocked                                     |
|--------------------|---------------------------------------------|
| `/`, `/index.html` | `/scripts/*`, `/tests/*`, `/docs/*`         |
| `/PUBLIC.KEY`      | `/.github/*`, `/CLAUDE.md`, `/packages.yml` |
| `/dists/*`         | `/Makefile`, `/_redirects`, etc.            |
| `/pool/*`          |                                             |

This prevents exposure of development files, configuration, and internal documentation.

## Quick Reference

| Pattern                      | Location                            |
|------------------------------|-------------------------------------|
| Input validation             | `scripts/lib/validation.sh`         |
| Checksum utilities           | `scripts/lib/checksums.sh`          |
| Path traversal protection    | `scripts/update-repo.sh`            |
| Script injection prevention  | `.github/workflows/update-repo.yml` |
| Access control middleware    | `functions/_middleware.js`          |

## External Resources

- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/)
