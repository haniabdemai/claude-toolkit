# task-pickup-guard

*Part of the [claude-project-tracker](../) system: its README explains the board vocabulary (cards, statuses, acceptance criteria) and how the hooks chain together.*

**Purpose: the moment the assistant reads a tracker card that isn't In
Progress, remind it: forcefully, that picking up a card means moving it
to In Progress and writing acceptance criteria first.**

The recurring failure this addresses: a session reads a To Do card,
understands the task, and dives straight into implementation. The board
still says To Do, no acceptance criteria exist, and by the end nobody can
say what "done" was supposed to mean. Status drift like this was the
single most repeated tracker violation before this hook existed.

This is the first of a three-hook chain:
**card-pickup-guard** (remind + arm) → [card-edit-guard](../task-edit-guard/)
(enforce) → [auto-checklist](../acceptance-checklist/) (fulfil + disarm).

## What it does

- Fires when the assistant fetches a tracker card whose status is To Do or
  Backlog (matched against a small local cache of tracker pages, so
  non-tracker page reads cost nothing and no API call is made in the hot
  path).
- Injects a non-blocking reminder (exit 0: the session legitimately needs
  to read the card) spelling out the pickup contract: move to In Progress,
  write acceptance criteria as to-do items, then start.
- **Arms the enforcement**: writes a session-scoped lockfile that
  card-edit-guard checks on every Edit/Write until the card actually moves.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "mcp__notion__API-retrieve-a-page",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/claude-project-tracker/task-pickup-guard/task-pickup-guard-hook.sh" }] }
    ]
  }
}
```

Match whatever tool your setup uses to read tracker items (add both MCP
variants if you have two Notion servers connected).

## Adapting it

- **Built for Notion**: the matcher names the Notion MCP read tool and the
  status lookup reads a Notion-page cache. On Jira or Linear, match your
  tracker MCP's read tool instead and fill the cache from a JQL / GraphQL
  status query: nothing else changes.
- Expects a small cache file mapping tracker page IDs to statuses,
  refreshed at session start by a companion script: swap in whatever
  "is this one of my tracker's cards, and what status?" lookup fits your
  tracker (Notion, Linear, Jira). Without the cache it silently no-ops.
- Session isolation comes from `../../lib/session-id.sh` (lockfiles keyed by
  the ancestor agent process), so two sessions reading different cards
  never trip each other.
