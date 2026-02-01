#!/usr/bin/env bash
#
# Test apt package installation in a Docker container.
#
# Usage:
#   ./tests/test-package.sh [package] [image]
#
# Examples:
#   ./tests/test-package.sh                              # Test first package on debian:bookworm-slim
#   ./tests/test-package.sh keystone-cli                 # Test keystone-cli on default image
#   ./tests/test-package.sh keystone-cli ubuntu:24.04    # Test on Ubuntu 24.04
#
# Requirements:
#   - Docker must be installed and running
#   - yq must be installed (brew install yq)
#   - The apt repository must be live at apt.knight-owl.dev
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${REPO_ROOT}/packages.yml"

# Load shared libraries
source "${REPO_ROOT}/scripts/lib/validation.sh"
source "${REPO_ROOT}/scripts/lib/require.sh"

# Check dependencies
require_yq || exit 1
require_docker || exit 1

# Get package name (default to first package in config)
PACKAGE="${1:-$(yq -r '.packages[0].name' "${CONFIG_FILE}")}"
IMAGE="${2:-debian:bookworm-slim}"

# Validate package name format (if user-provided)
if [[ -n "${1:-}" ]]; then
  validate_package_name "${PACKAGE}" || exit 1
fi

# Validate package exists in config
if ! yq -e ".packages[] | select(.name == \"${PACKAGE}\")" "${CONFIG_FILE}" &> /dev/null; then
  echo "Error: Package '${PACKAGE}' not found in packages.yml"
  echo "Available packages:"
  yq -r '.packages[].name' "${CONFIG_FILE}" | sed 's/^/  - /'
  exit 1
fi

# Get verify command (optional)
VERIFY_CMD=$(yq -r ".packages[] | select(.name == \"${PACKAGE}\") | .verify // \"\"" "${CONFIG_FILE}")

echo "Testing package: ${PACKAGE}"
echo "Image: ${IMAGE}"
echo "Verify command: ${VERIFY_CMD:-<none>}"
echo "==========================================="

docker run --rm \
  -e "PACKAGE=${PACKAGE}" \
  -e "VERIFY_CMD=${VERIFY_CMD}" \
  "${IMAGE}" bash -c '
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
echo "=== Installing $PACKAGE ==="
apt-get install -y "$PACKAGE"

echo ""
echo "=== Verifying installation ==="
dpkg -s "$PACKAGE" | grep -E "^(Package|Version|Status):"

if [ -n "$VERIFY_CMD" ]; then
    echo ""
    echo "=== Running verify command (as non-root user) ==="
    # Create non-root user to run verify command (more realistic)
    useradd -m testuser
    # Run via bash -c to properly handle quoted arguments with spaces
    runuser -u testuser -- bash -c "$VERIFY_CMD"
fi

echo ""
echo "==========================================="
echo "SUCCESS: $PACKAGE installed and working"
echo "==========================================="
'
