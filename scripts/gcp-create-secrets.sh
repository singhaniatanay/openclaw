#!/usr/bin/env bash
# Interactive helper to create the OpenClaw secrets in GCP Secret Manager.
# Each secret is created idempotently (no error if it already exists), then
# you're prompted to paste the value. Press Ctrl+D after pasting to commit.
# Type "skip" + Enter to skip a secret you've already populated.

set -u

PROJECT="${PROJECT:-alwyn-openclaw}"

create_or_skip() {
  local name="$1"
  if gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "[ok] secret $name already exists"
  else
    gcloud secrets create "$name" --replication-policy=automatic --project="$PROJECT" >/dev/null
    echo "[+]  created secret $name"
  fi
}

add_version() {
  local name="$1"
  local prompt="$2"
  echo
  echo "----- $name -----"
  echo "$prompt"
  echo "(paste value, then press Enter then Ctrl+D — or type 'skip' + Enter to skip)"
  local value
  value="$(cat)"
  if [ "$value" = "skip" ]; then
    echo "[--] skipped $name"
    return
  fi
  if [ -z "$value" ]; then
    echo "[!!] empty value for $name; skipping"
    return
  fi
  printf '%s' "$value" | gcloud secrets versions add "$name" --data-file=- --project="$PROJECT" >/dev/null
  echo "[ok] added version to $name"
}

generate_random() {
  local name="$1"
  local desc="$2"
  echo
  echo "----- $name -----"
  echo "Generating $desc (32 random hex bytes)..."
  openssl rand -hex 32 | gcloud secrets versions add "$name" --data-file=- --project="$PROJECT" >/dev/null
  echo "[ok] generated and stored $name"
}

generate_basic_auth() {
  local user_secret="caddy-basic-user"
  local hash_secret="caddy-basic-hash"
  echo
  echo "----- $user_secret + $hash_secret -----"
  read -r -p "Choose UI username (e.g. tanay): " user
  if [ -z "$user" ]; then
    echo "[!!] empty username; skipping basic auth"
    return
  fi
  read -r -s -p "Choose UI password: " pass
  echo
  if [ -z "$pass" ]; then
    echo "[!!] empty password; skipping basic auth"
    return
  fi
  printf '%s' "$user" | gcloud secrets versions add "$user_secret" --data-file=- --project="$PROJECT" >/dev/null
  echo "[ok] stored username in $user_secret"

  # Try local hashing tools; fall back to a python one-liner if available.
  local hash=""
  if command -v htpasswd >/dev/null 2>&1; then
    hash="$(htpasswd -bnBC 10 "" "$pass" | tr -d ':\n')"
  elif command -v python3 >/dev/null 2>&1; then
    hash="$(python3 -c 'import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(),bcrypt.gensalt(10)).decode())' "$pass" 2>/dev/null || true)"
  fi
  if [ -z "$hash" ]; then
    echo "[!!] no htpasswd or python3-bcrypt available; storing plaintext temporarily"
    echo "     (run 'pip3 install bcrypt' or 'brew install httpd' and rerun this section)"
    printf '%s' "PLAINTEXT:$pass" | gcloud secrets versions add "$hash_secret" --data-file=- --project="$PROJECT" >/dev/null
  else
    printf '%s' "$hash" | gcloud secrets versions add "$hash_secret" --data-file=- --project="$PROJECT" >/dev/null
    echo "[ok] stored bcrypt hash in $hash_secret"
  fi
  unset pass
}

# 1. Create empty secret resources (idempotent)
for s in \
  nvidia-api-key \
  discord-bot-token \
  memory-git-pat \
  openclaw-gateway-token \
  caddy-basic-user \
  caddy-basic-hash \
  discord-public-key \
  discord-application-id \
; do
  create_or_skip "$s"
done

# 2. Populate values
add_version nvidia-api-key      "Paste NVIDIA_API_KEY (from Render dashboard)"
add_version discord-bot-token   "Paste the new (rotated) Discord bot token"
add_version memory-git-pat      "Paste the GitHub PAT for the memory repo"
generate_random openclaw-gateway-token "OpenClaw gateway shared secret"
generate_basic_auth
add_version discord-public-key      "Paste Discord Application Public Key (Dev Portal -> General Information)"
add_version discord-application-id  "Paste Discord Application ID"

echo
echo "=========================================================="
gcloud secrets list --project="$PROJECT"
echo "=========================================================="
echo "Done. If any are missing a version, rerun this script."
