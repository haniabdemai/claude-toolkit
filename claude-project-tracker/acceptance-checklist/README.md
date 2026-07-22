# acceptance-checklist

*Part of the [claude-project-tracker](../) system: its README explains the board vocabulary (cards, statuses, acceptance criteria) and how the hooks chain together.*

**Purpose: the instant a card moves to In Progress, put the standard
acceptance-criteria checklist on it: automatically, so quality gates
exist before the first line of code.**

Asking an assistant to "always write acceptance criteria" works until it
doesn't. This hook removes the ask: moving a card to In Progress *is* the
trigger, and the checklist appears on the card as to-do blocks without
anyone remembering anything. It is the fulfilment step of the pickup chain
([card-pickup-guard](../task-pickup-guard/) →
[card-edit-guard](../task-edit-guard/) → **auto-checklist**).

## What it does

- Runs *after* a successful tracker update (PostToolUse). If the status
  changed to In Progress:
  - Inserts the standard acceptance criteria as to-do checkboxes into the
    card body via the Notion API: items like "verified from the user's
    perspective", "tested with real data", "docs updated if behaviour
    changed", "committed and pushed". Card-specific criteria get added on
    top by the session.
  - **Skips insertion if to-do blocks already exist** (idempotent: a card
    picked up twice doesn't get two checklists).
  - Clears the card-edit-guard lockfile, unblocking Edit/Write.
- The checklist matters beyond ceremony: the companion
  [testing-status-guard](../done-checklist-guard/) refuses to let a card
  reach Done with no to-do blocks, so this hook is what makes that gate
  satisfiable by default.

## Install

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "mcp__notion__API-patch-page",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/claude-project-tracker/acceptance-checklist/acceptance-checklist-hook.sh" }] }
    ]
  }
}
```

## Adapting it

- **Built for Notion**: it reacts to the Notion MCP page-update tool and
  inserts to-do blocks via the Notion REST API. On Jira, match your Jira
  MCP's issue-update tool and swap the insertion call for a checklist /
  subtask POST on the issue: the trigger logic stays identical.

- Needs a Notion integration token; the script reads it from a macOS
  Keychain item (service name `notion-api-key`: change at the top of the
  script, or swap the lookup for an env var on other platforms).
- The checklist text is a plain array in the script: make it your team's
  definition of done.
- Porting to another tracker means replacing one function: "append these
  checklist items to this card".
