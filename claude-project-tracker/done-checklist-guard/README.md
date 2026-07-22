# done-checklist-guard

*Part of the [claude-project-tracker](../) system: its README explains the board vocabulary (cards, statuses, acceptance criteria) and how the hooks chain together.*

**Purpose: make it impossible to mark work Done with no acceptance
criteria on the card.**

"Done" is the most abused word in AI-assisted development. The pattern
this hook killed: a session finishes coding, feels done, flips the card to
Done, and there is no checklist on the card, so nothing was ever verified
against anything. If the definition of done isn't written down, Done is
just a mood.

## What it does

Fires on tracker status changes:

- **→ In Progress:** non-blocking reminder (exit 0) to define acceptance
  criteria now: the standard set plus card-specific ones. (Normally
  [auto-checklist](../acceptance-checklist/) has already inserted them.)
- **→ Done:** fetches the card body via the Notion API and **blocks**
  (exit 2) if it contains no to-do blocks. No checklist, no Done:
  write the criteria and verify them first.
- Degrades gracefully: if the API call fails for any reason it falls back
  to a non-blocking warning rather than trapping the session, and cards
  created before the enforcement cut-over date are grandfathered.

Paired with auto-checklist this creates a closed loop: criteria appear
automatically at pickup, and cannot be skipped at close.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "mcp__notion__API-patch-page",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/claude-project-tracker/done-checklist-guard/done-checklist-guard-hook.sh" }] }
    ]
  }
}
```

## Adapting it

- **Built for Notion**: fires on the Notion MCP page-update tool and reads
  the card body via the Notion REST API. On Jira, match your issue-update
  tool and swap the body read for a checklist/subtask count on the issue.

- Same Notion token setup as auto-checklist (Keychain item
  `notion-api-key`, or swap for an env var).
- The status names ("In Progress", "Done") and the enforcement date are
  variables at the top of the script.
- The idea ports to any tracker with a body/checklist concept: block the
  terminal status when the checklist is absent.
