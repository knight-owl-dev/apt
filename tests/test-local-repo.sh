#!/usr/bin/env bash
#
# Test the update-repo.sh script locally and validate generated metadata.
#
# Usage:
#   ./tests/test-local-repo.sh [package[:version] ...]
#
# Examples:
#   ./tests/test-local-repo.sh                      # Test with all packages (latest)
#   ./tests/test-local-repo.sh keystone-cli:0.1.9   # Test with specific version
#
# This script:
#   1. Runs update-repo.sh to generate repository metadata
#   2. Validates Packages files have required fields
#   3. Validates Release file has correct checksums
#   4. Validates .deb files match their checksums
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_ROOT/packages.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAILED=1; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
info() { echo "  $1"; }

FAILED=0

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required. Install with: brew install yq (macOS) or snap install yq (Linux)"
    exit 1
fi

echo "=== Running update-repo.sh ==="
KEEP_ARTIFACTS=1 "$REPO_ROOT/scripts/update-repo.sh" "$@"
echo ""

echo "=== Validating generated metadata ==="

# Get architectures from config
mapfile -t ARCHS < <(yq -r '.packages[].architectures[]' "$CONFIG_FILE" | sort -u)

# Validate Packages files
echo ""
echo "--- Packages files ---"
for arch in "${ARCHS[@]}"; do
    packages_file="$REPO_ROOT/dists/stable/main/binary-$arch/Packages"

    if [[ ! -f "$packages_file" ]]; then
        fail "Missing: $packages_file"
        continue
    fi
    pass "Exists: binary-$arch/Packages"

    # Check required fields for each package entry
    while IFS= read -r pkg_name; do
        # Extract package block
        block=$(awk -v pkg="$pkg_name" '
            /^Package:/ { if ($2 == pkg) found=1; else found=0 }
            found { print }
            found && /^$/ { exit }
        ' "$packages_file")

        if [[ -z "$block" ]]; then
            fail "Package $pkg_name not found in binary-$arch/Packages"
            continue
        fi

        # Check required fields
        for field in Package Version Architecture Filename Size MD5sum SHA1 SHA256; do
            if echo "$block" | grep -q "^$field:"; then
                : # Field exists
            else
                fail "Package $pkg_name missing field: $field"
            fi
        done

        # Validate Filename path format
        filename=$(echo "$block" | grep "^Filename:" | cut -d' ' -f2)
        if [[ "$filename" =~ ^pool/main/[a-z]/.+/.+\.deb$ ]]; then
            pass "Package $pkg_name ($arch): valid Filename path"
        else
            fail "Package $pkg_name ($arch): invalid Filename path: $filename"
        fi

        # Validate checksum of actual .deb file
        deb_file="$REPO_ROOT/artifacts/$(basename "$filename")"
        if [[ -f "$deb_file" ]]; then
            expected_sha256=$(echo "$block" | grep "^SHA256:" | cut -d' ' -f2)
            if command -v sha256sum &>/dev/null; then
                actual_sha256=$(sha256sum "$deb_file" | cut -d' ' -f1)
            else
                actual_sha256=$(shasum -a 256 "$deb_file" | cut -d' ' -f1)
            fi

            if [[ "$expected_sha256" == "$actual_sha256" ]]; then
                pass "Package $pkg_name ($arch): SHA256 checksum matches"
            else
                fail "Package $pkg_name ($arch): SHA256 mismatch"
                info "Expected: $expected_sha256"
                info "Actual:   $actual_sha256"
            fi
        else
            warn "Package $pkg_name ($arch): .deb file not found for checksum validation (already cleaned up?)"
        fi

    done < <(yq -r ".packages[] | select(.architectures[] == \"$arch\") | .name" "$CONFIG_FILE")
done

# Validate Release file
echo ""
echo "--- Release file ---"
release_file="$REPO_ROOT/dists/stable/Release"

if [[ ! -f "$release_file" ]]; then
    fail "Missing: Release file"
else
    pass "Exists: Release"

    # Check required fields
    for field in Origin Label Suite Codename Architectures Components Date MD5Sum SHA1 SHA256; do
        if grep -q "^$field:" "$release_file"; then
            pass "Release has field: $field"
        else
            fail "Release missing field: $field"
        fi
    done

    # Validate checksums in Release match actual Packages files
    echo ""
    echo "--- Release checksums ---"
    for arch in "${ARCHS[@]}"; do
        packages_file="dists/stable/main/binary-$arch/Packages"
        packages_path="$REPO_ROOT/$packages_file"

        if [[ ! -f "$packages_path" ]]; then
            continue
        fi

        # Get expected SHA256 from Release (must be in SHA256 section, not MD5Sum or SHA1)
        expected=$(awk '/^SHA256:/{found=1; next} found && /^ /{print}' "$release_file" | grep "main/binary-$arch/Packages$" | grep -v ".gz" | awk '{print $1}')

        # Calculate actual SHA256
        if command -v sha256sum &>/dev/null; then
            actual=$(sha256sum "$packages_path" | cut -d' ' -f1)
        else
            actual=$(shasum -a 256 "$packages_path" | cut -d' ' -f1)
        fi

        if [[ "$expected" == "$actual" ]]; then
            pass "Release SHA256 for binary-$arch/Packages matches"
        else
            fail "Release SHA256 for binary-$arch/Packages mismatch"
            info "Expected: $expected"
            info "Actual:   $actual"
        fi
    done
fi

# Validate compressed Packages files
echo ""
echo "--- Compressed files ---"
for arch in "${ARCHS[@]}"; do
    packages_gz="$REPO_ROOT/dists/stable/main/binary-$arch/Packages.gz"
    packages_file="$REPO_ROOT/dists/stable/main/binary-$arch/Packages"

    if [[ ! -f "$packages_gz" ]]; then
        fail "Missing: binary-$arch/Packages.gz"
        continue
    fi
    pass "Exists: binary-$arch/Packages.gz"

    # Verify gzip decompresses to same content
    if diff -q <(gzip -dc "$packages_gz") "$packages_file" &>/dev/null; then
        pass "binary-$arch/Packages.gz decompresses correctly"
    else
        fail "binary-$arch/Packages.gz content mismatch"
    fi
done

# Clean up artifacts
rm -rf "$REPO_ROOT/artifacts"

echo ""
echo "=== Summary ==="
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All validations passed!${NC}"
    echo ""
    echo "Generated files:"
    echo "  - dists/stable/Release"
    for arch in "${ARCHS[@]}"; do
        echo "  - dists/stable/main/binary-$arch/Packages"
        echo "  - dists/stable/main/binary-$arch/Packages.gz"
    done
    echo ""
    echo "Note: Run 'git restore dists/' to discard local changes,"
    echo "      or 'git diff dists/' to review them."
else
    echo -e "${RED}Some validations failed!${NC}"
    exit 1
fi
