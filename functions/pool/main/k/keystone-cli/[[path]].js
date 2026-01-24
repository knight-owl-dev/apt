/**
 * Cloudflare Pages Function to redirect .deb package requests to GitHub Releases.
 *
 * Parses the version from the filename and redirects to the versioned release URL.
 *
 * Example:
 *   Request:  /pool/main/k/keystone-cli/keystone-cli_0.1.9_amd64.deb
 *   Redirect: https://github.com/knight-owl-dev/keystone-cli/releases/download/v0.1.9/keystone-cli_0.1.9_amd64.deb
 */
export function onRequest(context) {
  const url = new URL(context.request.url);
  const path = url.pathname;

  // Extract filename from path
  // Path: /pool/main/k/keystone-cli/keystone-cli_0.1.9_amd64.deb
  const filename = path.split('/').pop();

  // Parse version from filename: keystone-cli_{version}_{arch}.deb
  const match = filename.match(/^keystone-cli_([^_]+)_(amd64|arm64)\.deb$/);

  if (!match) {
    return new Response('Not found', { status: 404 });
  }

  const version = match[1];
  const redirectUrl = `https://github.com/knight-owl-dev/keystone-cli/releases/download/v${version}/${filename}`;

  return Response.redirect(redirectUrl, 302);
}
