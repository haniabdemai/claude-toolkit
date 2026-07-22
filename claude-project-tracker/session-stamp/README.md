# session-stamp

*Part of the [claude-project-tracker](../) system: its README explains the board vocabulary (cards, statuses, acceptance criteria) and how the hooks chain together.*

**Purpose: make the board double as a crash-recovery registry.** When a card
moves to In Progress, this stamps it with the session's resume identity, so if
that session later crashes or the machine reboots you can see which card was in
flight and pick straight back up.

The recurring failure it addresses: a session dies mid-task and you're left
guessing which of several sessions owned which card, and how to resume it.

## What it does

- Fires on a card update where `Status` becomes **In Progress**.
- Writes two properties on that card, itself (zero model tokens):
  - **Session ID**, the session UUID plus the working directory, e.g.
    `a1b2c3… @ /Users/you/project`.
  - **Session Started**, the timestamp.
- To resume after a crash: read the card, then
  `cd <dir> && claude --resume <session id>`.

Fail-open: a non-tracker page that happens to get `Status="In Progress"` lacks
these properties, so the write 400s harmlessly and nothing happens.

## Install

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "mcp__notion__API-patch-page",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/claude-project-tracker/session-stamp/session-stamp-hook.sh" }] }
    ]
  }
}
```

The token is read from `NOTION_TOKEN`, else the macOS Keychain item
`notion-api-key`, change the `get_token` block for your own secret store.
Your board needs a `Session ID` (text) and `Session Started` (date) property
for the stamp to land; the reference **Project Kanban** template already has
both.

## Adapting it

- **Built for Notion**: it PATCHes two Notion page properties. On another
  tracker, point the matcher at your update tool and swap the REST call for
  your tracker's field update.
- Pairs naturally with [session-start-gate-check](../session-start-gate-check/),
  which reads the board at startup, together they let a fresh session see both
  what is unfinished and which session last touched it.
