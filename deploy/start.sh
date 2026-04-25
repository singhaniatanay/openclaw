#!/usr/bin/env sh
set -eu

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CONFIG_PATH="$STATE_DIR/openclaw.json"
TEMPLATE_PATH="/app/deploy/openclaw.json.tmpl"
WORKSPACE_SEED="/app/deploy/workspace"
MEMORY_REPO_DIR="${MEMORY_REPO_DIR:-/data/memory}"
export MEMORY_REPO_DIR

mkdir -p "$STATE_DIR" "$WORKSPACE_DIR"

required="DISCORD_SERVER_ID DISCORD_USER_ID_1 DISCORD_USER_ID_2 NVIDIA_API_KEY DISCORD_BOT_TOKEN MAIN_CHANNEL_ID DIGEST_CHANNEL_ID"
missing=""
for var in $required; do
  eval "val=\${$var:-}"
  if [ -z "$val" ]; then missing="$missing $var"; fi
done
if [ -n "$missing" ]; then
  echo "FATAL: missing required env vars:$missing" >&2
  exit 1
fi

substitute() {
  sed \
    -e "s|\${DISCORD_SERVER_ID}|${DISCORD_SERVER_ID}|g" \
    -e "s|\${DISCORD_USER_ID_1}|${DISCORD_USER_ID_1}|g" \
    -e "s|\${DISCORD_USER_ID_2}|${DISCORD_USER_ID_2}|g" \
    -e "s|\${MAIN_CHANNEL_ID}|${MAIN_CHANNEL_ID}|g" \
    -e "s|\${DIGEST_CHANNEL_ID}|${DIGEST_CHANNEL_ID}|g" \
    "$1"
}

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Seeding config at $CONFIG_PATH from template"
  substitute "$TEMPLATE_PATH" > "$CONFIG_PATH"
fi

for f in USER.md AGENTS.md MEMORY.md; do
  if [ ! -f "$WORKSPACE_DIR/$f" ] && [ -f "$WORKSPACE_SEED/$f" ]; then
    echo "Seeding $WORKSPACE_DIR/$f"
    substitute "$WORKSPACE_SEED/$f" > "$WORKSPACE_DIR/$f"
  fi
done

# --- Memory sync setup (optional) ---
SYNC_PID=""
if [ -n "${MEMORY_GIT_REPO:-}" ] && [ -n "${MEMORY_GIT_PAT:-}" ]; then
  AUTH_REPO="https://x-access-token:${MEMORY_GIT_PAT}@${MEMORY_GIT_REPO#https://}"

  if [ ! -d "$MEMORY_REPO_DIR/.git" ]; then
    echo "Cloning memory repo"
    git clone --quiet "$AUTH_REPO" "$MEMORY_REPO_DIR"
  else
    echo "Memory repo already cloned; pulling latest"
    git -C "$MEMORY_REPO_DIR" pull --quiet --rebase --autostash || \
      echo "memory-sync: pull failed, continuing with local copy" >&2
  fi

  git -C "$MEMORY_REPO_DIR" config user.email "openclaw@render.local"
  git -C "$MEMORY_REPO_DIR" config user.name  "OpenClaw Bot"

  if [ ! -f "$MEMORY_REPO_DIR/MEMORY.md" ]; then
    cp "$WORKSPACE_SEED/MEMORY.md" "$MEMORY_REPO_DIR/MEMORY.md"
  fi

  rm -f "$WORKSPACE_DIR/MEMORY.md"
  ln -s "$MEMORY_REPO_DIR/MEMORY.md" "$WORKSPACE_DIR/MEMORY.md"

  /app/deploy/memory-sync.sh &
  SYNC_PID=$!
  echo "memory-sync started (pid $SYNC_PID, interval ${MEMORY_SYNC_INTERVAL_SECONDS:-300}s)"
else
  echo "MEMORY_GIT_REPO / MEMORY_GIT_PAT unset; memory will be ephemeral"
fi

# --- Health listener on Render's $PORT (binds immediately) ---
# Render's deploy times out if nothing listens on $PORT within ~5 minutes.
# The gateway takes ~4.5 min to boot, which races the timeout. Bind a
# tiny placeholder server right away so Render's port scan and health
# checks always succeed.
node /app/deploy/health-listener.mjs &
HEALTH_PID=$!
echo "health-listener started (pid $HEALTH_PID, port ${PORT:-10000})"

# --- Gateway with graceful shutdown ---
# Gateway runs on an internal loopback port — we don't expose it because
# Discord uses outbound websockets. Pin to 18789 to avoid conflicting
# with the health listener on $PORT.
export OPENCLAW_GATEWAY_PORT=18789
node openclaw.mjs gateway --bind lan --allow-unconfigured &
GATEWAY_PID=$!

cleanup() {
  trap - TERM INT EXIT
  echo "Shutdown received; flushing memory and stopping gateway"
  if [ -n "$SYNC_PID" ] && kill -0 "$SYNC_PID" 2>/dev/null; then
    kill -TERM "$SYNC_PID" 2>/dev/null || true
  fi
  if [ -d "$MEMORY_REPO_DIR/.git" ]; then
    cd "$MEMORY_REPO_DIR"
    if ! git diff --quiet -- MEMORY.md 2>/dev/null; then
      git add MEMORY.md
      git commit -m "memory: shutdown sync $(date -u +%FT%TZ)" --quiet 2>/dev/null || true
      git push --quiet 2>/dev/null || echo "shutdown push failed" >&2
    fi
  fi
  if [ -n "${HEALTH_PID:-}" ] && kill -0 "$HEALTH_PID" 2>/dev/null; then
    kill -TERM "$HEALTH_PID" 2>/dev/null || true
  fi
  if kill -0 "$GATEWAY_PID" 2>/dev/null; then
    kill -TERM "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup TERM INT

wait "$GATEWAY_PID"
