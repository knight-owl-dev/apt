#!/usr/bin/env bash
set -euo pipefail

#
# Install and verify an apt package inside a Docker container.
#
# This script is mounted into a Docker container by test-package.sh.
# It should not be run directly on the host.
#
# Environment variables (set by test-package.sh):
#   PACKAGE    - Package name to install
#   VERIFY_CMD - Optional command to verify the package works
#

# Required environment variables
: "${PACKAGE:?PACKAGE must be set}"
: "${VERIFY_CMD=}" # Optional, default to empty

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
echo "=== Installing ${PACKAGE} ==="
apt-get install -y "${PACKAGE}"

echo ""
echo "=== Verifying installation ==="
dpkg -s "${PACKAGE}" | grep -E "^(Package|Version|Status):"

if [[ -n "${VERIFY_CMD}" ]]; then
  echo ""
  echo "=== Running verify command (as non-root user) ==="
  # Create non-root user to run verify command (more realistic)
  useradd -m testuser
  # Run via bash -c to properly handle quoted arguments with spaces
  runuser -u testuser -- bash -c "${VERIFY_CMD}"
fi

echo ""
echo "==========================================="
echo "SUCCESS: ${PACKAGE} installed and working"
echo "==========================================="
