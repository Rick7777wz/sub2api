#!/usr/bin/env bash
# =============================================================================
# sync-upstream.sh
# -----------------------------------------------------------------------------
# Pull the latest changes from the official Sub2API repo (Wei-Shaw/sub2api)
# into YOUR fork while keeping your local modifications (e.g. the Claude OAuth
# client_id in backend/internal/pkg/oauth/oauth.go).
#
# After a successful merge, push to your fork's origin. That push triggers the
# GitHub Actions workflow, which rebuilds and pushes the image to GHCR.
#
# Usage:
#   ./deploy/sync-upstream.sh            # merge the latest upstream RELEASE tag
#   ./deploy/sync-upstream.sh main       # merge upstream main branch instead
#   ./deploy/sync-upstream.sh v1.2.3     # merge a specific upstream tag/ref
#
# Requirements: git. Run from anywhere inside the repo.
# =============================================================================
set -euo pipefail

UPSTREAM_URL="https://github.com/Wei-Shaw/sub2api.git"
TARGET_REF="${1:-}"

cd "$(git rev-parse --show-toplevel)"

# 1. Ensure an 'upstream' remote points at the official repo.
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "[info] adding 'upstream' remote -> $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

echo "[info] fetching upstream (with tags)..."
git fetch --tags --prune upstream

# 2. Resolve which upstream ref to merge.
if [ -z "$TARGET_REF" ]; then
  TARGET_REF="$(git ls-remote --tags --sort=-v:refname upstream 'v*' \
    | awk -F/ '{print $3}' | grep -v '\^{}' | head -n1 || true)"
  if [ -z "$TARGET_REF" ]; then
    echo "[warn] no version tag found, falling back to upstream/main"
    TARGET_REF="upstream/main"
  fi
fi

echo "[info] current branch : $(git rev-parse --abbrev-ref HEAD)"
echo "[info] merging ref     : $TARGET_REF"

# 3. Safety: refuse to run with a dirty tree (commit your changes first).
if [ -n "$(git status --porcelain)" ]; then
  echo "[error] working tree is not clean. Commit or stash your changes first:"
  git status --short
  exit 1
fi

# 4. Merge upstream. Keep history so the merge is easy to audit/revert.
if git merge --no-edit "$TARGET_REF"; then
  echo
  echo "[ok] merged $TARGET_REF cleanly. Your modifications are preserved."
  echo "[next] push to trigger the cloud image rebuild:"
  echo "         git push origin $(git rev-parse --abbrev-ref HEAD)"
else
  echo
  echo "[conflict] merge stopped on conflicts (most likely oauth.go)."
  echo "           Resolve them, keeping YOUR client_id values, then:"
  echo "             git add <files> && git commit --no-edit"
  echo "             git push origin $(git rev-parse --abbrev-ref HEAD)"
  echo "           To abort instead:  git merge --abort"
  exit 1
fi
