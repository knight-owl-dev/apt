#!/usr/bin/env bash
# Shared validation functions for package names and versions

# Validate package name format (lowercase alphanumeric with hyphens)
# Usage: validate_package_name "package-name"
validate_package_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Error: Invalid package name '$name'. Must be lowercase alphanumeric with hyphens." >&2
    return 1
  fi
}

# Validate version format (semver: X.Y.Z or X.Y.Z-prerelease)
# Usage: validate_version "1.0.0"
validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version '$version'. Must be semver format (e.g., 1.0.0 or 1.0.0-beta.1)." >&2
    return 1
  fi
}
