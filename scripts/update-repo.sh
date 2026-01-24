#!/usr/bin/env bash
set -euo pipefail

# Update apt repository metadata for all configured packages
#
# Usage: ./scripts/update-repo.sh [package[:version] ...]
#
# Examples:
#   ./scripts/update-repo.sh                      # All packages, latest versions
#   ./scripts/update-repo.sh keystone-cli         # Only keystone-cli, latest version
#   ./scripts/update-repo.sh keystone-cli:0.1.9   # Only keystone-cli, specific version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_ROOT/packages.yml"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"

# Parse command line arguments into associative array
declare -A VERSIONS
declare -a REQUESTED_PACKAGES=()
for arg in "$@"; do
    if [[ "$arg" == *:* ]]; then
        package="${arg%%:*}"
        version="${arg#*:}"
        VERSIONS["$package"]="$version"
    else
        package="$arg"
        # Version will be fetched later
    fi
    REQUESTED_PACKAGES+=("$package")
done

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required. Install with: brew install yq (macOS) or snap install yq (Linux)"
    exit 1
fi

# Read package list and architectures from config
mapfile -t ALL_PACKAGES < <(yq -r '.packages[].name' "$CONFIG_FILE")
mapfile -t ALL_ARCHS < <(yq -r '.packages[].architectures[]' "$CONFIG_FILE" | sort -u)

# Use requested packages or all packages
if [[ ${#REQUESTED_PACKAGES[@]} -gt 0 ]]; then
    PACKAGES=("${REQUESTED_PACKAGES[@]}")
else
    PACKAGES=("${ALL_PACKAGES[@]}")
fi

mkdir -p "$ARTIFACTS_DIR"

# Download packages
echo "==> Downloading packages..."
for package in "${PACKAGES[@]}"; do
    # Validate package exists in config
    if ! yq -e ".packages[] | select(.name == \"$package\")" "$CONFIG_FILE" &>/dev/null; then
        echo "Error: Package '$package' not found in packages.yml"
        exit 1
    fi
    repo=$(yq -r ".packages[] | select(.name == \"$package\") | .repo" "$CONFIG_FILE")
    mapfile -t archs < <(yq -r ".packages[] | select(.name == \"$package\") | .architectures[]" "$CONFIG_FILE")

    # Get version from args or fetch latest
    if [[ -v "VERSIONS[$package]" ]]; then
        version="${VERSIONS[$package]}"
    else
        echo "Fetching latest version for $package..."
        version=$(gh release view --repo "$repo" --json tagName -q '.tagName' | sed 's/^v//')
    fi
    VERSIONS["$package"]="$version"
    echo "Package $package: version $version"

    for arch in "${archs[@]}"; do
        deb_file="${package}_${version}_${arch}.deb"
        url="https://github.com/${repo}/releases/download/v${version}/${deb_file}"
        echo "Downloading: $deb_file"
        curl -fSL -o "$ARTIFACTS_DIR/$deb_file" "$url"
    done
done

# Generate Packages files for each architecture
echo "==> Generating Packages files..."
for arch in "${ALL_ARCHS[@]}"; do
    packages_dir="$REPO_ROOT/dists/stable/main/binary-${arch}"
    mkdir -p "$packages_dir"
    packages_file="$packages_dir/Packages"

    # Clear existing Packages file
    > "$packages_file"

    for package in "${PACKAGES[@]}"; do
        # Check if this package supports this architecture
        if ! yq -e ".packages[] | select(.name == \"$package\") | .architectures[] | select(. == \"$arch\")" "$CONFIG_FILE" &>/dev/null; then
            continue
        fi

        version="${VERSIONS[$package]}"
        deb_file="$ARTIFACTS_DIR/${package}_${version}_${arch}.deb"

        if [[ ! -f "$deb_file" ]]; then
            echo "Warning: $deb_file not found, skipping"
            continue
        fi

        # Extract control file
        dpkg-deb -f "$deb_file" > "$ARTIFACTS_DIR/control"

        # Calculate checksums
        size=$(stat -c%s "$deb_file" 2>/dev/null || stat -f%z "$deb_file")
        md5=$(md5sum "$deb_file" 2>/dev/null | cut -d' ' -f1 || md5 -q "$deb_file")
        sha1=$(sha1sum "$deb_file" 2>/dev/null | cut -d' ' -f1 || shasum -a 1 "$deb_file" | cut -d' ' -f1)
        sha256=$(sha256sum "$deb_file" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$deb_file" | cut -d' ' -f1)

        # Determine pool path (first letter of package name)
        first_letter="${package:0:1}"

        # Append to Packages file
        {
            cat "$ARTIFACTS_DIR/control"
            echo "Filename: pool/main/${first_letter}/${package}/${package}_${version}_${arch}.deb"
            echo "Size: $size"
            echo "MD5sum: $md5"
            echo "SHA1: $sha1"
            echo "SHA256: $sha256"
            echo ""
        } >> "$packages_file"

        echo "Added $package ($arch) to Packages"
    done

    # Create compressed version
    gzip -9 -c "$packages_file" > "$packages_file.gz"
done

# Generate Release file
echo "==> Generating Release file..."
cd "$REPO_ROOT/dists/stable"

{
    echo "Origin: Knight Owl"
    echo "Label: Knight Owl"
    echo "Suite: stable"
    echo "Codename: stable"
    echo "Architectures: ${ALL_ARCHS[*]}"
    echo "Components: main"
    echo "Date: $(date -Ru)"
    echo "MD5Sum:"
    for f in main/binary-*/Packages main/binary-*/Packages.gz; do
        [ -f "$f" ] || continue
        size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
        md5=$(md5sum "$f" 2>/dev/null | cut -d' ' -f1 || md5 -q "$f")
        printf " %s %8d %s\n" "$md5" "$size" "$f"
    done
    echo "SHA1:"
    for f in main/binary-*/Packages main/binary-*/Packages.gz; do
        [ -f "$f" ] || continue
        size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
        sha1=$(sha1sum "$f" 2>/dev/null | cut -d' ' -f1 || shasum -a 1 "$f" | cut -d' ' -f1)
        printf " %s %8d %s\n" "$sha1" "$size" "$f"
    done
    echo "SHA256:"
    for f in main/binary-*/Packages main/binary-*/Packages.gz; do
        [ -f "$f" ] || continue
        size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
        sha256=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$f" | cut -d' ' -f1)
        printf " %s %8d %s\n" "$sha256" "$size" "$f"
    done
} > Release

echo "==> Release file generated:"
cat Release

# Clean up
rm -rf "$ARTIFACTS_DIR"

echo "==> Done! Remember to sign the Release file."
