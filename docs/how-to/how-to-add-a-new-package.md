# How to Add a New Package

This guide explains how to add a new package to the `apt` repository.

## Prerequisites

- The package must be hosted on GitHub Releases
- Release tags must use semver format with `v` prefix (e.g., `v1.0.0`, `v2.1.0-beta.1`)
- Release assets must follow the naming convention: `<package>_{version}_{arch}.deb`
- Releases must include a `SHA256SUMS` file for checksum verification
- Supported architectures: `amd64`, `arm64`

## Steps

### 1. Add the package to packages.yml

Edit `packages.yml` in the repository root:

```yaml
packages:
  - name: keystone-cli
    repo: knight-owl-dev/keystone-cli
    architectures:
      - amd64
      - arm64
    verify: keystone-cli info

  - name: my-new-package
    repo: knight-owl-dev/my-new-package
    architectures:
      - amd64
      - arm64
    verify: my-new-package --version  # optional: command to verify in tests
```

Fields:

| Field           | Required | Description                                      |
|-----------------|----------|--------------------------------------------------|
| `name`          | Yes      | Package name (must match .deb filename prefix)   |
| `repo`          | Yes      | GitHub repository in `owner/repo` format         |
| `architectures` | Yes      | List of supported architectures                  |
| `verify`        | No       | Command to run in tests to verify installation   |

### 2. Create the Cloudflare Function

Create a redirect function at `functions/pool/main/<letter>/<package>/[[path]].js`.

For a package named `my-new-package`, create:

```plain
functions/pool/main/m/my-new-package/[[path]].js
```

Contents (copy and modify from keystone-cli):

```javascript
/**
 * Cloudflare Pages Function to redirect .deb package requests to GitHub Releases.
 *
 * Example:
 *   Request:  /pool/main/m/my-new-package/my-new-package_1.0.0_amd64.deb
 *   Redirect: https://github.com/knight-owl-dev/my-new-package/releases/download/v1.0.0/my-new-package_1.0.0_amd64.deb
 */
export function onRequest(context) {
  const url = new URL(context.request.url);
  const path = url.pathname;

  const filename = path.split('/').pop();

  // Update the regex to match your package name
  // Version must be semver: X.Y.Z or X.Y.Z-prerelease (e.g., 1.0.0, 2.1.0-beta.1)
  const match = filename.match(/^my-new-package_(\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?)_(amd64|arm64)\.deb$/);

  if (!match) {
    return new Response('Not found', { status: 404 });
  }

  const version = match[1];
  // Update the GitHub repository URL
  const redirectUrl = `https://github.com/knight-owl-dev/my-new-package/releases/download/v${version}/${filename}`;

  return Response.redirect(redirectUrl, 302);
}
```

### 3. Test locally (optional)

Generate the repository metadata locally to verify the configuration:

```bash
# Requires: yq, gh CLI, dpkg-deb
./scripts/update-repo.sh my-new-package:1.0.0
```

This downloads the `.deb`, extracts metadata, and generates `Packages` and `Release` files.

> **Important:** Do not commit the generated `dists/` files from local testing. They are
> unsigned and will be overwritten by the workflow. Discard them before committing:

```bash
git restore dists/
```

### 4. Commit and push

Commit only the configuration and function files:

```bash
git add packages.yml functions/
git commit -m "Add my-new-package to apt repository"
git push
```

### 5. Trigger the workflow

After pushing, trigger the GitHub Actions workflow to generate signed metadata:

1. Go to GitHub Actions → **Update Repository**
2. Click **Run workflow**
3. Optionally specify versions (e.g., `my-new-package:1.0.0`)

The workflow will:

1. Download `.deb` files for all packages
2. Generate `Packages` and `Release` files
3. Sign with GPG
4. Commit and push to `main`

### 6. Verify installation

Test that the package installs correctly:

```bash
./tests/test-package.sh my-new-package
```

Or test on a specific distribution:

```bash
./tests/test-package.sh my-new-package ubuntu:24.04
```

## Directory Structure

After adding a package, the repository structure should include:

```plain
packages.yml                                    # Updated with new package
functions/pool/main/m/my-new-package/[[path]].js  # New redirect function
dists/stable/main/binary-amd64/Packages         # Updated with new package metadata
dists/stable/main/binary-arm64/Packages         # Updated with new package metadata
```

## Troubleshooting

### Package not found during workflow

Verify the GitHub release exists and contains correctly named `.deb` files:

```bash
gh release view v1.0.0 --repo knight-owl-dev/my-new-package
```

Expected assets:

```plain
my-new-package_1.0.0_amd64.deb
my-new-package_1.0.0_arm64.deb
```

### 404 when downloading .deb via apt

Check the Cloudflare Function:

1. Verify the function path matches the pool path in `Packages` file
2. Verify the regex matches your package naming convention
3. Check Cloudflare Pages deployment logs for errors

### Test fails with "Package not found in packages.yml"

Ensure the package name in `packages.yml` exactly matches what you pass to the test script.
