#!/usr/bin/env sh
# Background sync loop: every $MEMORY_SYNC_INTERVAL_SECONDS, if MEMORY.md
# has changed since last successful push, commit and push to the private
# memory repo cloned at $MEMORY_REPO_DIR.
#
# Designed to be killed at any time (signal or process death). The trap in
# start.sh handles the SIGTERM final-push case.
set -eu

REPO_DIR="${MEMORY_REPO_DIR:-/data/memory}"
INTERVAL="${MEMORY_SYNC_INTERVAL_SECONDS:-300}"

cd "$REPO_DIR"

while :; do
  sleep "$INTERVAL"

  if git diff --quiet -- MEMORY.md 2>/dev/null; then
    continue
  fi

  git add MEMORY.md
  git commit -m "memory: auto-update $(date -u +%FT%TZ)" --quiet || continue
  if git push --quiet 2>/dev/null; then
    echo "memory-sync: pushed"
  else
    echo "memory-sync: push failed (will retry on next interval)" >&2
  fi
done
