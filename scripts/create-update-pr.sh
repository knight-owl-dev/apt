#!/usr/bin/env bash
set -euo pipefail

# Create a pull request for apt repository updates
#
# Usage: ./scripts/create-update-pr.sh
#
# Environment variables (required):
#   GH_TOKEN           - PAT for push and PR creation (must have repo scope)
#   GITHUB_RUN_ID      - Workflow run ID for unique branch naming
#   GITHUB_REPOSITORY  - Repository in "owner/repo" format
#
# Environment variables (optional):
#   VERSIONS           - Package specs for PR title (e.g., "keystone-cli:0.1.9")
#
# This script:
#   1. Configures git user (bot credentials)
#   2. Stages dists/ changes
#   3. Exits gracefully if no changes
#   4. Creates a uniquely-named branch
#   5. Commits and pushes changes
#   6. Creates a PR with auto-merge enabled

# Required environment variables (set by GitHub Actions)
: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

# Configure git user (bot credentials)
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Stage dists/ changes
git add dists/

# Check for actual changes
if git diff --staged --quiet; then
  echo "No changes to commit"
  exit 0
fi

# Create branch with unique run ID
BRANCH="update-repo/${GITHUB_RUN_ID}"
git checkout -b "${BRANCH}"

# Generate PR title based on versions input
if [[ -n "${VERSIONS:-}" ]]; then
  TITLE="Update repository: ${VERSIONS}"
else
  TITLE="Update repository: all packages"
fi

# Commit changes
git commit -m "${TITLE}"

# Configure git to use PAT for push (triggers CI workflow via pull_request event)
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git push -u origin "${BRANCH}"

# Create PR
PR_URL=$(gh pr create --title "${TITLE}" --body "Automated apt repository metadata update.")

# Enable auto-merge (squash)
if ! gh pr merge --auto --squash "${PR_URL}"; then
  echo "Failed to enable auto-merge for PR: ${PR_URL}"
  echo "Ensure auto-merge is enabled in repository settings and branch protection allows it."
  exit 1
fi

echo "Created PR: ${PR_URL}"
