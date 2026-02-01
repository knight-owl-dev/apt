#!/usr/bin/env bash
set -euo pipefail

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
  -v "${SCRIPT_DIR}/docker-install.sh:/install.sh:ro" \
  "${IMAGE}" bash /install.sh
