# Render deployment bootstrap

Files in this directory are baked into the Docker image and seed the runtime
on container start.

## Files

- `openclaw.json.tmpl` — runtime config template; channel/user IDs are
  substituted at boot from process env.
- `workspace/USER.md` — user profile injected into every Discord session.
- `workspace/AGENTS.md` — workspace instructions including channel layout,
  the cross-channel summary rule, and channel-naming conventions.
- `workspace/MEMORY.md` — initial seed for long-term memory; replaced at
  boot by a symlink into the private memory repo (see below).
- `start.sh` — entrypoint used by Render (`dockerCommand: /app/deploy/start.sh`).
- `memory-sync.sh` — background loop that auto-commits and pushes changes
  to `MEMORY.md` on a polling interval.

## Boot sequence

1. Validate required env vars: `DISCORD_SERVER_ID`, `DISCORD_USER_ID_1`,
   `DISCORD_USER_ID_2`, `MAIN_CHANNEL_ID`, `DIGEST_CHANNEL_ID`,
   `NVIDIA_API_KEY`, `DISCORD_BOT_TOKEN`. Hard-fail if any are missing.
2. Render the openclaw.json template into `$OPENCLAW_STATE_DIR/openclaw.json`
   (idempotent — preserves an existing on-disk file if present).
3. Seed `$OPENCLAW_WORKSPACE_DIR/{USER,AGENTS,MEMORY}.md` from `workspace/`,
   substituting channel ID env vars in AGENTS.md.
4. **Memory persistence:** if `MEMORY_GIT_REPO` and `MEMORY_GIT_PAT` are set:
   - Clone (or pull) the private memory repo to `/data/memory`.
   - Replace `$OPENCLAW_WORKSPACE_DIR/MEMORY.md` with a symlink to
     `/data/memory/MEMORY.md`.
   - Launch `memory-sync.sh` in the background.
5. Run `node openclaw.mjs gateway --bind lan` in the foreground.
6. On `SIGTERM` (sent by Render before container kill), do one final commit
   and push of MEMORY.md, then forward the signal to the gateway.

## Memory persistence model

Render's free tier doesn't support persistent disks, so `/data` is wiped on
every cold start. To keep `MEMORY.md` durable across restarts, we mirror it
into a private GitHub repo. The agent reads/writes the symlinked file as
normal; a polling sync loop (default 5 min) pushes any change.

Hard cases handled:

- **Cold start with prior state**: `git clone` rehydrates the latest
  `MEMORY.md` before the gateway starts.
- **Concurrent edits across redeploys**: only one container writes the
  repo at a time, so push conflicts are rare. If they occur, the loop
  retries on the next interval.
- **Sudden kill (SIGKILL after grace expired)**: changes since last sync
  are lost. Mitigation: keep `MEMORY_SYNC_INTERVAL_SECONDS` low if you
  expect frequent unscheduled kills.

## Updating

Editing files here only takes effect on the next image rebuild. Render
auto-rebuilds when the `deploy/render-config` branch is pushed.
