#!/usr/bin/env bash
#
# Test apt package installation in a Docker container.
#
# Usage:
#   ./tests/test-keystone-cli.sh [image]
#
# Examples:
#   ./tests/test-keystone-cli.sh                    # Uses debian:bookworm-slim (default)
#   ./tests/test-keystone-cli.sh ubuntu:24.04       # Test on Ubuntu 24.04
#   ./tests/test-keystone-cli.sh debian:bullseye    # Test on Debian 11
#
# Requirements:
#   - Docker must be installed and running
#   - The apt repository must be live at apt.knight-owl.dev
#

set -euo pipefail

IMAGE="${1:-debian:bookworm-slim}"

echo "Testing apt installation on $IMAGE"
echo "==========================================="

docker run --rm "$IMAGE" bash -c '
set -e

echo "=== Adding Knight Owl apt repository ==="
apt-get update
apt-get install -y curl gnupg ca-certificates

echo ""
echo "=== Importing GPG key ==="
curl -fsSL https://apt.knight-owl.dev/PUBLIC.KEY | gpg --dearmor -o /usr/share/keyrings/knight-owl.gpg
gpg --no-default-keyring --keyring /usr/share/keyrings/knight-owl.gpg --list-keys

echo ""
echo "=== Adding repository ==="
echo "deb [signed-by=/usr/share/keyrings/knight-owl.gpg] https://apt.knight-owl.dev stable main" > /etc/apt/sources.list.d/knight-owl.list
cat /etc/apt/sources.list.d/knight-owl.list

echo ""
echo "=== Updating package lists ==="
apt-get update

echo ""
echo "=== Installing keystone-cli ==="
apt-get install -y keystone-cli

echo ""
echo "=== Verifying installation ==="
which keystone-cli
keystone-cli info

echo ""
echo "=== Checking man page ==="
man -w keystone-cli

echo ""
echo "==========================================="
echo "SUCCESS: keystone-cli installed and working"
echo "==========================================="
'
