/**
 * Middleware to block access to development files.
 *
 * Allowed paths (apt repository):
 *   /                              - Landing page
 *   /index.html                    - Landing page
 *   /PUBLIC.KEY                    - GPG public key
 *   /dists/...                     - Release, InRelease, Packages, Packages.gz
 *   /pool/...                      - .deb downloads (handled by package functions)
 *
 * Blocked paths (development files):
 *   /scripts/*, /tests/*, /docs/*, /.github/*
 *   /CLAUDE.md, /packages.yml, /Makefile, etc.
 */
export async function onRequest(context) {
  const url = new URL(context.request.url);
  const path = url.pathname;

  // Allowed exact paths
  const allowedExact = ['/', '/index.html', '/PUBLIC.KEY'];

  // Allowed path prefixes (apt routes)
  const allowedPrefixes = ['/dists', '/pool/'];

  if (
    allowedExact.includes(path) ||
    allowedPrefixes.some((prefix) => path.startsWith(prefix))
  ) {
    return context.next();
  }

  // Block everything else
  return new Response('Not Found', { status: 404 });
}
