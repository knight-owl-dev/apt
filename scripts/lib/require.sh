#!/usr/bin/env bash
# Dependency check functions

# Require Bash 4+ (for mapfile, associative arrays)
# Usage: require_bash4
require_bash4() {
  if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "Error: Bash 4+ is required (found ${BASH_VERSION})." >&2
    echo "On macOS, install with: brew install bash" >&2
    return 1
  fi
}

# Require a command to be available
# Usage: require_command "command" "install instructions"
require_command() {
  local cmd="$1"
  local install_hint="${2:-}"
  if ! command -v "${cmd}" &> /dev/null; then
    echo "Error: ${cmd} is required.${install_hint:+ ${install_hint}}" >&2
    return 1
  fi
}

# Require yq to be available
# Usage: require_yq
require_yq() {
  require_command "yq" "Install with: brew install yq (macOS) or snap install yq (Linux)"
}

# Require gh CLI to be available
# Usage: require_gh
require_gh() {
  require_command "gh" "Install from: https://cli.github.com/"
}

# Require docker to be available
# Usage: require_docker
require_docker() {
  require_command "docker" "Install from: https://docs.docker.com/get-docker/"
}

# Require dpkg-deb to be available (for extracting .deb metadata)
# Usage: require_dpkg
require_dpkg() {
  require_command "dpkg-deb" "Install dpkg tools for your platform"
}
