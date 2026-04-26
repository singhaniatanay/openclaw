#!/usr/bin/env bash
# Tiny inline startup script attached to the VM as instance metadata.
# Bootstraps git + clones the repo, then hands off to deploy/gcp/setup.sh
# inside the repo so we can iterate on setup logic via git pushes without
# recreating the VM.
set -eu

LOG=/var/log/openclaw-bootstrap.log
exec > >(tee -a "$LOG") 2>&1
echo "===== bootstrap $(date -u +%FT%TZ) ====="

REPO_DIR=/opt/openclaw
REPO_HOST="${REPO_HOST:-github.com}"
REPO_PATH="${REPO_PATH:-singhaniatanay/openclaw.git}"
REPO_BRANCH="${REPO_BRANCH:-deploy/render-config}"
PROJECT="${PROJECT:-alwyn-openclaw}"

if ! command -v git >/dev/null; then
  apt-get update -y
  apt-get install -y git
fi

# Fetch deploy PAT from Secret Manager (reuses memory-git-pat, which has repo scope).
DEPLOY_PAT="$(gcloud secrets versions access latest --secret=memory-git-pat --project="$PROJECT" 2>/dev/null)"
if [ -z "$DEPLOY_PAT" ]; then
  echo "FATAL: could not fetch memory-git-pat from Secret Manager" >&2
  exit 1
fi
AUTH_URL="https://x-access-token:${DEPLOY_PAT}@${REPO_HOST}/${REPO_PATH}"

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --branch "$REPO_BRANCH" "$AUTH_URL" "$REPO_DIR"
else
  git -C "$REPO_DIR" remote set-url origin "$AUTH_URL"
  git -C "$REPO_DIR" fetch --prune origin
  git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
fi

bash "$REPO_DIR/deploy/gcp/setup.sh"
