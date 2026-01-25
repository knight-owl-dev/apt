#!/usr/bin/env bash
set -euo pipefail

# Update apt repository metadata for all configured packages
#
# Usage: ./scripts/update-repo.sh [package[:version] ...]
#
# Examples:
#   ./scripts/update-repo.sh                      # Update all packages to latest versions
#   ./scripts/update-repo.sh keystone-cli         # Update keystone-cli to latest, keep others unchanged
#   ./scripts/update-repo.sh keystone-cli:0.1.9   # Update keystone-cli to 0.1.9, keep others unchanged
#
# Note: The repository always includes ALL packages from packages.yml. When specific
# packages are provided, only those get version updates; others retain their current versions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_ROOT/packages.yml"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"

# Load shared libraries
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/checksums.sh"
source "$SCRIPT_DIR/lib/require.sh"

# Parse command line arguments into associative array
declare -A VERSIONS
declare -a REQUESTED_PACKAGES=()
for arg in "$@"; do
    if [[ "$arg" == *:* ]]; then
        package="${arg%%:*}"
        version="${arg#*:}"
        validate_package_name "$package" || exit 1
        validate_version "$version" || exit 1
        VERSIONS["$package"]="$version"
    else
        package="$arg"
        validate_package_name "$package" || exit 1
        # Version will be fetched later
    fi
    REQUESTED_PACKAGES+=("$package")
done

# Check dependencies
require_bash4 || exit 1
require_yq || exit 1
require_gh || exit 1
require_dpkg || exit 1

# Fetch SHA256SUMS file from a GitHub release (if available)
# Caches the result in ARTIFACTS_DIR to avoid re-downloading
# Returns 0 if checksums file exists, 1 if not available
fetch_checksums_file() {
    local repo="$1"
    local version="$2"
    local checksums_file="$ARTIFACTS_DIR/.checksums-${repo//\//-}-v${version}"

    # Return cached file if already downloaded
    if [[ -f "$checksums_file" ]]; then
        echo "$checksums_file"
        return 0
    fi

    # Try common checksums file names
    local base_url="https://github.com/${repo}/releases/download/v${version}"
    for name in SHA256SUMS SHA256SUMS.txt checksums.txt checksums-sha256.txt; do
        if curl -fsSL -o "$checksums_file" "${base_url}/${name}" 2>/dev/null; then
            echo "$checksums_file"
            return 0
        fi
    done

    # No checksums file found
    return 1
}

# Verify a file's SHA256 checksum against a checksums file
# Format supported: "<hash>  <filename>" or "<hash> *<filename>" (GNU coreutils)
verify_checksum() {
    local file="$1"
    local checksums_file="$2"
    local filename
    filename=$(basename "$file")

    # Extract expected checksum for this file
    local expected
    expected=$(awk -v f="$filename" '
        {
            # Handle both "hash  filename" and "hash *filename" formats
            gsub(/^\*/, "", $2)
            if ($2 == f) { print $1; exit }
        }
    ' "$checksums_file")

    if [[ -z "$expected" ]]; then
        echo "Warning: No checksum found for $filename in checksums file"
        return 1
    fi

    # Compute actual checksum
    local actual
    if ! actual=$(get_sha256 "$file"); then
        echo "Error: Failed to compute SHA256 for $file"
        return 1
    fi

    # Compare (exact match - SHA256 hashes are conventionally lowercase)
    if [[ "$expected" != "$actual" ]]; then
        echo "Error: Checksum mismatch for $filename"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi

    echo "Verified: $filename"
    return 0
}

# Download and verify a .deb file
# Requires SHA256SUMS file to be present in the release for verification
download_and_verify() {
    local repo="$1"
    local version="$2"
    local deb_file="$3"
    local dest="$4"

    # Fetch checksums file first (required)
    local checksums_file
    if ! checksums_file=$(fetch_checksums_file "$repo" "$version"); then
        echo "Error: No SHA256SUMS file found for $repo v$version"
        echo "Releases must include a checksums file (SHA256SUMS, SHA256SUMS.txt, checksums.txt, or checksums-sha256.txt)"
        exit 1
    fi

    local url="https://github.com/${repo}/releases/download/v${version}/${deb_file}"
    echo "Downloading: $deb_file"
    curl -fSL -o "$dest" "$url"

    # Verify checksum
    if ! verify_checksum "$dest" "$checksums_file"; then
        echo "Error: Checksum verification failed for $deb_file"
        rm -f "$dest"
        exit 1
    fi
}

# Read package list and architectures from config
mapfile -t ALL_PACKAGES < <(yq -r '.packages[].name' "$CONFIG_FILE")
mapfile -t ALL_ARCHS < <(yq -r '.packages[].architectures[]' "$CONFIG_FILE" | sort -u)

# Determine which packages to process
# Note: We always regenerate metadata for ALL packages to keep the repository consistent.
# The REQUESTED_PACKAGES only controls which packages get fresh downloads (for version updates).
if [[ ${#REQUESTED_PACKAGES[@]} -gt 0 ]]; then
    UPDATE_PACKAGES=("${REQUESTED_PACKAGES[@]}")
else
    UPDATE_PACKAGES=("${ALL_PACKAGES[@]}")
fi

# Ensure artifacts directory is safe (no symlink path traversal)
if [[ -L "$ARTIFACTS_DIR" ]]; then
    echo "Error: $ARTIFACTS_DIR is a symlink, refusing to continue"
    exit 1
fi
mkdir -p "$ARTIFACTS_DIR"
# Verify resolved path stays within repository
REAL_ARTIFACTS="$(realpath "$ARTIFACTS_DIR")"
REAL_REPO="$(realpath "$REPO_ROOT")"
if [[ "$REAL_ARTIFACTS" != "$REAL_REPO/artifacts" ]]; then
    echo "Error: Artifacts directory resolves outside repository: $REAL_ARTIFACTS"
    exit 1
fi

# Download packages (only those being updated)
echo "==> Downloading packages..."
for package in "${UPDATE_PACKAGES[@]}"; do
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
        download_and_verify "$repo" "$version" "$deb_file" "$ARTIFACTS_DIR/$deb_file"
    done
done

# For packages not being updated, fetch their current version from existing Packages file
echo "==> Resolving versions for unchanged packages..."
for package in "${ALL_PACKAGES[@]}"; do
    if [[ ! -v "VERSIONS[$package]" ]]; then
        # Try to get version from existing Packages files across all architectures
        existing_version=""
        for arch in "${ALL_ARCHS[@]}"; do
            pkgs_file="$REPO_ROOT/dists/stable/main/binary-$arch/Packages"
            if [[ -f "$pkgs_file" ]]; then
                existing_version=$(awk -v pkg="$package" '
                    /^Package:/ { current_pkg = $2 }
                    /^Version:/ && current_pkg == pkg { print $2; exit }
                ' "$pkgs_file")
                if [[ -n "$existing_version" ]]; then
                    break
                fi
            fi
        done
        if [[ -n "$existing_version" ]]; then
            VERSIONS["$package"]="$existing_version"
            echo "Package $package: using existing version $existing_version"
        else
            echo "Error: No version found for $package (not in args, not in existing metadata)"
            exit 1
        fi
    fi
done

# Download any missing packages (those with existing versions but no local .deb)
for package in "${ALL_PACKAGES[@]}"; do
    repo=$(yq -r ".packages[] | select(.name == \"$package\") | .repo" "$CONFIG_FILE")
    mapfile -t archs < <(yq -r ".packages[] | select(.name == \"$package\") | .architectures[]" "$CONFIG_FILE")
    version="${VERSIONS[$package]}"

    for arch in "${archs[@]}"; do
        deb_file="$ARTIFACTS_DIR/${package}_${version}_${arch}.deb"
        if [[ ! -f "$deb_file" ]]; then
            echo "Downloading missing: ${package}_${version}_${arch}.deb"
            download_and_verify "$repo" "$version" "${package}_${version}_${arch}.deb" "$deb_file"
        fi
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

    for package in "${ALL_PACKAGES[@]}"; do
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
        if ! size=$(get_file_size "$deb_file"); then
            echo "Error: Failed to get file size for $deb_file"
            exit 1
        fi
        if ! md5=$(get_md5 "$deb_file"); then
            echo "Error: Failed to compute MD5 for $deb_file"
            exit 1
        fi
        if ! sha1=$(get_sha1 "$deb_file"); then
            echo "Error: Failed to compute SHA1 for $deb_file"
            exit 1
        fi
        if ! sha256=$(get_sha256 "$deb_file"); then
            echo "Error: Failed to compute SHA256 for $deb_file"
            exit 1
        fi

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
        size=$(get_file_size "$f")
        md5=$(get_md5 "$f")
        printf " %s %8d %s\n" "$md5" "$size" "$f"
    done
    echo "SHA1:"
    for f in main/binary-*/Packages main/binary-*/Packages.gz; do
        [ -f "$f" ] || continue
        size=$(get_file_size "$f")
        sha1=$(get_sha1 "$f")
        printf " %s %8d %s\n" "$sha1" "$size" "$f"
    done
    echo "SHA256:"
    for f in main/binary-*/Packages main/binary-*/Packages.gz; do
        [ -f "$f" ] || continue
        size=$(get_file_size "$f")
        sha256=$(get_sha256 "$f")
        printf " %s %8d %s\n" "$sha256" "$size" "$f"
    done
} > Release

echo "==> Release file generated:"
cat Release

# Clean up (skip with KEEP_ARTIFACTS=1 for testing)
if [[ "${KEEP_ARTIFACTS:-}" != "1" ]]; then
    rm -rf "$ARTIFACTS_DIR"
fi

echo "==> Done! Remember to sign the Release file."
