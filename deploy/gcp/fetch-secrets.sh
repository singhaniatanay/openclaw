#!/usr/bin/env bash
# Pull secrets from GCP Secret Manager into /run/openclaw/openclaw.env.
# Runs as ExecStartPre before openclaw.service. /run is tmpfs so the file
# disappears on reboot — secrets are re-fetched fresh on each start.
set -eu

PROJECT="${PROJECT:-alwyn-openclaw}"
ENV_DIR=/run/openclaw
ENV_FILE="$ENV_DIR/openclaw.env"

mkdir -p "$ENV_DIR"
chmod 700 "$ENV_DIR"

fetch() {
  gcloud secrets versions access latest --secret="$1" --project="$PROJECT" 2>/dev/null
}

# Compose env file. Static config + secret values.
{
  cat <<'STATIC'
OPENCLAW_STATE_DIR=/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/data/workspace
MEMORY_REPO_DIR=/data/memory
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_BIND=loopback
DISCORD_SERVER_ID=1467439984096313354
DISCORD_USER_ID_1=905160890997940245
DISCORD_USER_ID_2=522465064322727956
MAIN_CHANNEL_ID=1497695325866037379
DIGEST_CHANNEL_ID=1497695345927389204
MEMORY_GIT_REPO=https://github.com/singhaniatanay/openclaw-memory.git
MEMORY_SYNC_INTERVAL_SECONDS=300
STATIC
  printf 'NVIDIA_API_KEY=%s\n'         "$(fetch nvidia-api-key)"
  printf 'DISCORD_BOT_TOKEN=%s\n'      "$(fetch discord-bot-token)"
  printf 'MEMORY_GIT_PAT=%s\n'         "$(fetch memory-git-pat)"
  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$(fetch openclaw-gateway-token)"
} > "$ENV_FILE"

chmod 600 "$ENV_FILE"

# Caddy env file (separate so caddy.service can EnvironmentFile= it).
CADDY_ENV=/run/caddy/.env
mkdir -p /run/caddy
chmod 755 /run/caddy
{
  printf 'CADDY_BASIC_USER=%s\n' "$(fetch caddy-basic-user)"
  printf 'CADDY_BASIC_HASH=%s\n' "$(fetch caddy-basic-hash)"
} > "$CADDY_ENV"
chmod 644 "$CADDY_ENV"
