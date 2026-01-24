#!/usr/bin/env bash
set -euo pipefail

# Sign the Release file with GPG
#
# Usage: ./scripts/sign-release.sh
#
# Environment variables:
#   GPG_PASSPHRASE  - Passphrase for the GPG key (required for non-interactive use)
#   GPG_KEY_ID      - Key ID to use for signing (optional, auto-selects if only one key exists)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$REPO_ROOT/dists/stable"

cd "$RELEASE_DIR"

if [[ ! -f Release ]]; then
    echo "Error: Release file not found at $RELEASE_DIR/Release"
    exit 1
fi

# Determine which GPG key to use
KEY_ID="${GPG_KEY_ID:-}"

if [[ -z "$KEY_ID" ]]; then
    # Auto-select only if exactly one secret key exists
    mapfile -t KEY_IDS < <(gpg --list-secret-keys --keyid-format=long --with-colons 2>/dev/null | awk -F: '$1=="sec"{print $5}')

    if (( ${#KEY_IDS[@]} == 0 )); then
        echo "Error: No GPG secret key found"
        exit 1
    elif (( ${#KEY_IDS[@]} > 1 )); then
        echo "Error: Multiple GPG secret keys found. Set GPG_KEY_ID to the desired key ID."
        exit 1
    fi
    KEY_ID="${KEY_IDS[0]}"
fi

echo "Signing with key: $KEY_ID"

# Create InRelease (clearsigned)
gpg --default-key "$KEY_ID" \
    --batch --yes \
    --pinentry-mode loopback \
    --passphrase "${GPG_PASSPHRASE:-}" \
    --clearsign \
    -o InRelease \
    Release

# Create Release.gpg (detached signature)
gpg --default-key "$KEY_ID" \
    --batch --yes \
    --pinentry-mode loopback \
    --passphrase "${GPG_PASSPHRASE:-}" \
    --armor --detach-sign \
    -o Release.gpg \
    Release

echo "Generated InRelease and Release.gpg"
