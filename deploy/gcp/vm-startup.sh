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
REPO_URL="${REPO_URL:-https://github.com/singhaniatanay/openclaw.git}"
REPO_BRANCH="${REPO_BRANCH:-deploy/render-config}"

if ! command -v git >/dev/null; then
  apt-get update -y
  apt-get install -y git
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
else
  git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
  git -C "$REPO_DIR" fetch --prune origin
  git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
fi

bash "$REPO_DIR/deploy/gcp/setup.sh"
