#!/usr/bin/env bash
set -euo pipefail

# Sign the Release file with GPG
# Usage: GPG_PASSPHRASE=xxx ./scripts/sign-release.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$REPO_ROOT/dists/stable"

cd "$RELEASE_DIR"

if [[ ! -f Release ]]; then
    echo "Error: Release file not found at $RELEASE_DIR/Release"
    exit 1
fi

KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)

if [[ -z "$KEY_ID" ]]; then
    echo "Error: No GPG secret key found"
    exit 1
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
