# session-start-gate-check

*Part of the [claude-project-tracker](../) system: its README explains the board vocabulary (cards, statuses, acceptance criteria) and how the hooks chain together.*

**Purpose: begin every session by looking at the board, surface everything
half-finished, and prime the other hooks.** This is the proactive counterpart
to the guards: instead of waiting for you to touch a card, it opens with
"here is what is not actually done yet."

It also does something the rest of the system depends on: it writes the small
cache that [task-pickup-guard](../task-pickup-guard/) reads. **Without this
hook running at session start, task-pickup-guard has no cache and silently
does nothing**, so this is a prerequisite for the pickup → edit → checklist
chain, not an optional extra.

## What it does

On `SessionStart` it queries the board once and:

- **Reports incomplete gates**, cards that are Done but not committed /
  pushed / tested, cards in Done / In Progress / Review with no
  acceptance-criteria checklist, and Feature/POC cards in In Progress / Review
  with no plan or test approach. Each is listed as
  `[Project] "Card", Done but not pushed, no acceptance criteria`.
- **Writes the tracker cache** `/tmp/tracker-card-cache.json` mapping every
  card id to `{status, title}`, so task-pickup-guard can tell a tracker card
  from any other page with zero API calls.
- **Reminds** the session to open a card before starting work.

Zero-token and fail-open: it prints to the session context and always exits 0,
so it can never stop a session from starting.

## Install

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command",
                    "command": "python3 /path/to/claude-project-tracker/session-start-gate-check/check-gates.py" }] }
    ]
  }
}
```

Then configure two things (both read from the environment):

- `TRACKER_DATABASE_ID`, your board's database id (the 32-hex-char id in the
  board URL).
- The Notion integration token, `NOTION_TOKEN`, or the macOS Keychain item
  `notion-api-key` (change `get_token()` for your own secret store).

## Adapting it

- **Built for Notion**: it calls the Notion REST API to read the board and its
  card bodies. On Jira / Linear, replace `query_database()` and `fetch_blocks()`
  with your tracker's status query and checklist lookup; the gate logic and the
  cache format stay the same.
- The gate rules (which Types are "code", which fields make up the entry/exit
  gates) are plain constants near the top, tune them to your board's schema.
- The cache it writes is the exact shape task-pickup-guard expects
  (`{card_id: {status, title}}`, keyed by dashed UUID), so the two are designed
  to be installed together.
