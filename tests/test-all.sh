#!/usr/bin/env bash
#
# Test all packages from packages.yml
#
# Usage:
#   ./tests/test-all.sh [image]
#
# Examples:
#   ./tests/test-all.sh                    # Test all packages on debian:bookworm-slim
#   ./tests/test-all.sh ubuntu:24.04       # Test all packages on Ubuntu 24.04
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_ROOT/packages.yml"
IMAGE="${1:-debian:bookworm-slim}"

# Load shared libraries
source "$REPO_ROOT/scripts/lib/require.sh"

# Check dependencies
require_bash4 || exit 1
require_yq || exit 1

mapfile -t PACKAGES < <(yq -r '.packages[].name' "$CONFIG_FILE")

echo "Testing ${#PACKAGES[@]} package(s) on $IMAGE"
echo "==========================================="
echo ""

FAILED=()

for package in "${PACKAGES[@]}"; do
    echo ">>> Testing: $package"
    if "$SCRIPT_DIR/test-package.sh" "$package" "$IMAGE"; then
        echo ">>> PASSED: $package"
    else
        echo ">>> FAILED: $package"
        FAILED+=("$package")
    fi
    echo ""
done

echo "==========================================="
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "All ${#PACKAGES[@]} package(s) passed"
    exit 0
else
    echo "FAILED: ${FAILED[*]}"
    exit 1
fi
