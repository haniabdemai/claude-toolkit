# task-edit-guard

*Part of the [claude-project-tracker](../) system: its README explains the board vocabulary (cards, statuses, acceptance criteria) and how the hooks chain together.*

**Purpose: physically stop implementation from starting while the tracker
card still says To Do.**

[card-pickup-guard](../task-pickup-guard/) *reminds*; this hook *enforces*.
Reminders get forgotten the moment the model is deep in a task: that is
precisely the state in which it starts editing files. This guard makes the
workflow rule mechanical: no Edit or Write lands while a picked-up card
hasn't been moved to In Progress.

## What it does

- On every Edit/Write, checks for the lockfile card-pickup-guard wrote when
  a To Do/Backlog card was fetched this session.
- Lockfile present → **block** (exit 2) with instructions: move the card to
  In Progress, write acceptance criteria, then continue. The lockfile is
  cleared automatically by [auto-checklist](../acceptance-checklist/) when the
  card actually moves (or can be deleted manually to dismiss a
  false-positive pickup).
- Engineering details: a fast path exits in ~2ms when no lockfiles exist
  at all (this hook runs on *every* file edit, so the common case must be
  free); lockfiles are session-scoped (keyed by ancestor agent PID via
  `../../lib/session-id.sh`) with a 4-hour TTL; any error in detection
  fails open (exit 0): a broken guard must never block legitimate work.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/claude-project-tracker/task-edit-guard/task-edit-guard-hook.sh" }] }
    ]
  }
}
```

## Adapting it

Nothing tracker-specific lives in this script: it only honours the
lockfile contract. Point card-pickup-guard at your tracker and this hook
works unchanged.
