# How to Configure Cloudflare Pages

This guide documents the Cloudflare Pages setup for the `apt` repository.

## Overview

Cloudflare Pages serves two purposes:

1. **Static hosting** — serves apt metadata, GPG public key, and landing page
2. **Functions** — redirects `.deb` download requests to GitHub Releases

## Build Configuration

| Setting                | Value                                                             |
|------------------------|-------------------------------------------------------------------|
| Production branch      | `main`                                                            |
| Build command          | `npx markdown-to-html-cli --source README.md --output index.html` |
| Build output directory | `/`                                                               |

### Landing Page Generation

The `README.md` file is the source of truth for the landing page. During each deployment,
Cloudflare runs the build command which converts `README.md` to `index.html` with basic
styling.

To update the landing page, edit `README.md` and push — Cloudflare rebuilds automatically.

### Why not commit index.html?

- Single source of truth (`README.md`)
- No drift between README and landing page
- GitHub renders `README.md` nicely; visitors to `apt.knight-owl.dev` get styled HTML

## Custom Domain

The repository is served at `apt.knight-owl.dev`.

### DNS Configuration

| Type  | Name  | Value               | TTL (seconds) |
|-------|-------|---------------------|---------------|
| CNAME | `apt` | `apt-d5z.pages.dev` | 600           |

DNS is managed at GoDaddy. Cloudflare Pages handles SSL automatically.

## Functions

Cloudflare Pages Functions live in the `functions/` directory and handle dynamic requests.

### Package Download Redirect

**Path:** `functions/pool/main/k/keystone-cli/[[path]].js`

Handles requests to `/pool/main/k/keystone-cli/*.deb`:

1. Parses the version from the filename (e.g., `keystone-cli_0.1.9_amd64.deb` → `0.1.9`)
2. Returns a 302 redirect to the GitHub Releases URL

```plain
Request:  /pool/main/k/keystone-cli/keystone-cli_0.1.9_amd64.deb
Redirect: https://github.com/knight-owl-dev/keystone-cli/releases/download/v0.1.9/keystone-cli_0.1.9_amd64.deb
```

This allows the `apt` repository to reference packages without storing binaries.

## Adding a New Package

To add redirects for a new package (e.g., `another-tool`):

1. Create the function directory:

   ```plain
   functions/pool/main/a/another-tool/
   ```

2. Add `[[path]].js` with appropriate redirect logic

3. Update the workflow to generate metadata for the new package

## Deployment

Cloudflare Pages deploys automatically on every push to `main`. No manual action required.

To check deployment status:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to Workers & Pages → `apt` project
3. View deployment history and logs

## Troubleshooting

### Build fails

Check the build logs in Cloudflare dashboard. Common issues:

- `npx` command not found — ensure build command is correct
- README.md missing — verify file exists in repo root

### Function returns 404

Verify the request path matches the function route:

- Function: `functions/pool/main/k/keystone-cli/[[path]].js`
- Handles: `/pool/main/k/keystone-cli/*`

### Custom domain not working

1. Verify DNS CNAME record points to the `.pages.dev` URL
2. Check Cloudflare Pages → Custom domains for SSL status
3. DNS propagation may take up to 24 hours (usually faster)
