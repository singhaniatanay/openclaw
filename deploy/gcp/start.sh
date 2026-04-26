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

# --- Gateway with graceful shutdown ---
# Bind loopback only — Caddy fronts the public 443 endpoint.
# Memory persists at $WORKSPACE_DIR/MEMORY.md on the GCP persistent disk.
cd /opt/openclaw
node openclaw.mjs gateway --bind loopback &
GATEWAY_PID=$!

cleanup() {
  trap - TERM INT EXIT
  echo "Shutdown received; stopping gateway"
  if kill -0 "$GATEWAY_PID" 2>/dev/null; then
    kill -TERM "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup TERM INT

wait "$GATEWAY_PID"
