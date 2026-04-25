# Agent Workspace Instructions

This file is injected into every Discord channel session.

## Channel layout

The Discord server is structured as:

- **Hub category**
  - `#main` (`channel:${MAIN_CHANNEL_ID}`) — receives one-line summaries when you complete non-trivial tasks anywhere else
  - `#digest` (`channel:${DIGEST_CHANNEL_ID}`) — receives the daily rollup (cron-driven; do not post here ad-hoc)
  - `#announcements` — humans only; do not post
- **Projects category** (`#project-*`) — long-lived per-project context
- **Tasks category** (`#task-*`) — short-lived, one task per channel
- **Agent category**
  - `#agent-config` — talk to me about your own config or model
  - `#agent-logs` — operational signals only

Each channel has its own isolated session. You are *not* sharing memory across channels except via `MEMORY.md` (loaded on demand) and these bootstrap files.

## Cross-channel summary rule

When you complete a non-trivial task in any project or task channel, post a one-line
summary to `#main` using the message tool. Skip for clarifications, questions,
single-message replies, or tool errors.

Format: `[#<source-channel>] <one-line summary of what you did>`

Tool call:

```
message(action="send", channel="discord",
        target="channel:${MAIN_CHANNEL_ID}",
        message="[#<source-channel>] <summary>")
```

## Channel creation

You have `Manage Channels` on this server. When the user asks for a new task or project
channel, create it under the appropriate category and start working in it. Naming:

- Tasks: `task-<short-kebab-slug>` (e.g. `task-fix-auth-bug`)
- Projects: `project-<name>` (e.g. `project-alpha`)

Confirm the channel name before creating if there's any ambiguity.

## Memory

- Read `MEMORY.md` on demand via `memory_search` / `memory_get` when long-term context matters.
- Write to `MEMORY.md` only for facts that should persist across sessions: user preferences, project decisions, active goals. Not transient state.
- **Note:** This deployment runs on Render's free tier without a persistent disk, so `MEMORY.md` resets on every cold start (~15 min idle). Treat it as a session-bounded scratchpad, not durable storage.
