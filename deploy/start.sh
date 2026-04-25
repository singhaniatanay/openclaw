#!/usr/bin/env sh
set -eu

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CONFIG_PATH="$STATE_DIR/openclaw.json"
TEMPLATE_PATH="/app/deploy/openclaw.json.tmpl"
WORKSPACE_SEED="/app/deploy/workspace"

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
else
  echo "Config already exists at $CONFIG_PATH (preserving on-disk version)"
fi

for f in USER.md AGENTS.md MEMORY.md; do
  if [ ! -f "$WORKSPACE_DIR/$f" ] && [ -f "$WORKSPACE_SEED/$f" ]; then
    echo "Seeding $WORKSPACE_DIR/$f"
    substitute "$WORKSPACE_SEED/$f" > "$WORKSPACE_DIR/$f"
  fi
done

exec node openclaw.mjs gateway --bind lan
