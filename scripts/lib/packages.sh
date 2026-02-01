#!/usr/bin/env bash
# Debian Packages file parsing functions

# Get version for a package from a Packages file
# Usage: get_package_version "package-name" "/path/to/Packages"
# Returns: version string or empty if not found
get_package_version() {
  local pkg="$1"
  local packages_file="$2"
  awk -v pkg="$pkg" '
        /^Package:/ { current_pkg = $2 }
        /^$/ { current_pkg = "" }
        /^Version:/ && current_pkg == pkg { print $2; exit }
    ' "$packages_file"
}

# Get entire stanza for a package from a Packages file
# Usage: get_package_block "package-name" "/path/to/Packages"
# Returns: full package block or empty if not found
get_package_block() {
  local pkg="$1"
  local packages_file="$2"
  awk -v pkg="$pkg" '
        /^Package:/ { if ($2 == pkg) found=1; else found=0 }
        found { print }
        found && /^$/ { exit }
    ' "$packages_file"
}
