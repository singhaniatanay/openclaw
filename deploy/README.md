# Render deployment bootstrap

Files in this directory are baked into the Docker image and seed the persistent
disk on first container start.

## Files

- `openclaw.json.tmpl` — runtime config template; `${DISCORD_SERVER_ID}` and
  `${DISCORD_USER_ID}` are substituted at boot from process env.
- `workspace/USER.md` — user profile injected into every Discord session.
- `workspace/AGENTS.md` — workspace instructions including the cross-channel
  summary rule and channel-naming conventions.
- `workspace/MEMORY.md` — empty long-term memory scaffold.
- `start.sh` — entrypoint used by Render (`dockerCommand: /app/deploy/start.sh`).

## Boot sequence

1. Validate required env vars: `DISCORD_SERVER_ID`, `DISCORD_USER_ID_1`,
   `DISCORD_USER_ID_2`, `MAIN_CHANNEL_ID`, `DIGEST_CHANNEL_ID`,
   `NVIDIA_API_KEY`, `DISCORD_BOT_TOKEN`. Hard-fail if any are missing.
2. If `$OPENCLAW_STATE_DIR/openclaw.json` does not exist, render the template
   from env vars and write it. (On Render's free tier the disk is ephemeral, so
   this happens on every cold start. That's fine — idempotent.)
3. Seed `$OPENCLAW_WORKSPACE_DIR/{USER,AGENTS,MEMORY}.md` from `workspace/`,
   substituting channel ID env vars in AGENTS.md.
4. `exec node openclaw.mjs gateway --bind lan` so Render can reach the port.

## Updating

Editing files here only takes effect on a fresh disk (or after deleting the
corresponding files on the persistent disk). To change the running config,
either edit the file in place via Render shell or run `openclaw config set`.
