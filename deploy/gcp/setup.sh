#!/usr/bin/env bash
# Idempotent VM provisioning for OpenClaw on Debian. Safe to rerun on every boot.
# - Installs Node 24, pnpm, Caddy, git on first run (marker file).
# - Pulls latest code from this repo.
# - Builds (no-op if no changes).
# - Installs systemd units for openclaw + caddy override + secret fetcher.
# - Starts services.
set -eu

LOG=/var/log/openclaw-setup.log
exec > >(tee -a "$LOG") 2>&1
echo "===== openclaw setup $(date -u +%FT%TZ) ====="

REPO_DIR=/opt/openclaw
REPO_URL=${REPO_URL:-https://github.com/singhaniatanay/openclaw.git}
REPO_BRANCH=${REPO_BRANCH:-deploy/render-config}
INSTALL_MARKER=/var/lib/openclaw/installed
DATA_DIR=/data

mkdir -p /var/lib/openclaw "$DATA_DIR" /run/openclaw

# ---------- 1. One-time package install ----------
if [ ! -f "$INSTALL_MARKER" ]; then
  echo "[setup] first-time package install"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl git ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https jq build-essential

  # NodeSource Node 24
  if ! command -v node >/dev/null || [ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" -lt 22 ]; then
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    apt-get install -y nodejs
  fi

  # pnpm via corepack (bundled with Node)
  corepack enable
  corepack prepare pnpm@9 --activate

  # Caddy
  if ! command -v caddy >/dev/null; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -y
    apt-get install -y caddy
  fi

  touch "$INSTALL_MARKER"
fi

# ---------- 2. Repo clone / update ----------
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "[setup] cloning $REPO_URL"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
else
  echo "[setup] updating repo"
  git -C "$REPO_DIR" fetch --prune origin
  git -C "$REPO_DIR" checkout "$REPO_BRANCH"
  git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
fi

# ---------- 3. Build OpenClaw ----------
echo "[setup] pnpm install + build"
cd "$REPO_DIR"
pnpm install --frozen-lockfile
pnpm build

# ---------- 4. Install Caddy config ----------
install -m 0644 "$REPO_DIR/deploy/gcp/Caddyfile" /etc/caddy/Caddyfile

# Caddy systemd override to load env file fetched from Secret Manager.
mkdir -p /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/override.conf <<'EOF'
[Service]
EnvironmentFile=/run/caddy/.env
EOF

# ---------- 5. Install OpenClaw systemd unit ----------
chmod +x "$REPO_DIR/deploy/gcp/fetch-secrets.sh" "$REPO_DIR/deploy/gcp/start.sh" "$REPO_DIR/deploy/memory-sync.sh"
install -m 0644 "$REPO_DIR/deploy/gcp/openclaw.service" /etc/systemd/system/openclaw.service

# ---------- 6. Make sure secrets file exists before first start ----------
"$REPO_DIR/deploy/gcp/fetch-secrets.sh"

# ---------- 7. Reload + enable + start ----------
systemctl daemon-reload
systemctl enable --now caddy.service
systemctl enable --now openclaw.service
systemctl restart caddy.service
systemctl restart openclaw.service

echo "===== openclaw setup done $(date -u +%FT%TZ) ====="
