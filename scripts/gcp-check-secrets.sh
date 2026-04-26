#!/usr/bin/env bash
set -u
PROJECT="${PROJECT:-alwyn-openclaw}"
for s in \
  nvidia-api-key \
  discord-bot-token \
  memory-git-pat \
  openclaw-gateway-token \
  caddy-basic-user \
  caddy-basic-hash \
  discord-public-key \
  discord-application-id
do
  v=$(gcloud secrets versions list "$s" --filter="state:ENABLED" --format="value(name)" --project="$PROJECT" 2>/dev/null | head -1)
  printf "%-26s %s\n" "$s" "${v:-MISSING}"
done
