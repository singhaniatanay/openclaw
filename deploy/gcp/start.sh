#!/usr/bin/env bash
# OpenClaw gateway launcher for GCP VM. No reverse proxy here — Caddy fronts
# 443 -> 127.0.0.1:18789. Memory sync still runs in the background.
set -eu

# Source env file populated by fetch-secrets.sh.
ENV_FILE=/run/openclaw/openclaw.env
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CONFIG_PATH="$STATE_DIR/openclaw.json"
TEMPLATE_PATH="/opt/openclaw/deploy/gcp/openclaw.json.tmpl"
WORKSPACE_SEED="/opt/openclaw/deploy/workspace"
MEMORY_REPO_DIR="${MEMORY_REPO_DIR:-/data/memory}"
export MEMORY_REPO_DIR

mkdir -p "$STATE_DIR" "$WORKSPACE_DIR"

required="DISCORD_SERVER_ID DISCORD_USER_ID_1 DISCORD_USER_ID_2 NVIDIA_API_KEY DISCORD_BOT_TOKEN MAIN_CHANNEL_ID DIGEST_CHANNEL_ID OPENCLAW_GATEWAY_TOKEN"
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

  git -C "$MEMORY_REPO_DIR" config user.email "openclaw@gcp.local"
  git -C "$MEMORY_REPO_DIR" config user.name  "OpenClaw Bot"

  if [ ! -f "$MEMORY_REPO_DIR/MEMORY.md" ] && [ -f "$WORKSPACE_SEED/MEMORY.md" ]; then
    cp "$WORKSPACE_SEED/MEMORY.md" "$MEMORY_REPO_DIR/MEMORY.md"
  fi

  rm -f "$WORKSPACE_DIR/MEMORY.md"
  ln -s "$MEMORY_REPO_DIR/MEMORY.md" "$WORKSPACE_DIR/MEMORY.md"

  /opt/openclaw/deploy/memory-sync.sh &
  SYNC_PID=$!
  echo "memory-sync started (pid $SYNC_PID, interval ${MEMORY_SYNC_INTERVAL_SECONDS:-300}s)"
else
  echo "MEMORY_GIT_REPO / MEMORY_GIT_PAT unset; memory will be ephemeral"
fi

# --- Gateway with graceful shutdown ---
# Bind loopback only — Caddy fronts the public 443 endpoint.
cd /opt/openclaw
node openclaw.mjs gateway --bind loopback &
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
  if kill -0 "$GATEWAY_PID" 2>/dev/null; then
    kill -TERM "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup TERM INT

wait "$GATEWAY_PID"
