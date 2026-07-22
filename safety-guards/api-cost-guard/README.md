# api-cost-guard

*One of the independent [safety-guards](../): adopt it alone or with its siblings.*

**Purpose: make an AI assistant stop and justify scope before it runs batch
operations against APIs that cost money: even when it delegates the work
to a subagent.**

An agent iterating over 500 items with a paid API in the loop is one
enthusiastic moment away from a real bill. The failure mode this guards
against is not malice, it is momentum: the assistant is mid-task, the loop
is "obviously" the next step, and nobody priced it. This guard forces a
pause exactly at that moment.

Two scripts, one mechanism:

- `api-cost-guard-hook.sh`: intercepts Bash commands (env-var patterns, script
  names, HTTP clients, `gh workflow run`, batch-shaped invocations).
- `api-cost-guard-agent-hook.sh`: intercepts **Agent dispatches** whose prompts
  describe API work, closing the "do it in a subagent" loophole.

## What it does

A two-step lockfile handshake that the model cannot shortcut:

1. First attempt: the hook blocks (exit 2) and presents five scope
   criteria (what API, how many calls, what does it cost, what protections
   exist, has the user approved this scope).
2. The assistant presents those criteria to the user and gets approval.
3. The re-run with `SCOPE_APPROVED=1` passes **only if the lockfile from
   step 1 exists**: proving the block actually fired and the approval was
   given in response to it, not pre-emptively self-granted.

Free/no-risk APIs can be exempted (the original exempts the Notion API).
If `~/.claude/api-cost-rules.md` exists, its contents (your billing caps
and approved services) are included in the block message so the assistant
reasons against your actual rules.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/safety-guards/api-cost-guard/api-cost-guard-hook.sh" }] },
      { "matcher": "Agent",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/safety-guards/api-cost-guard/api-cost-guard-agent-hook.sh" }] }
    ]
  }
}
```

## Adapting it

- Detection is generic pattern matching (env vars, HTTP clients, batch
  verbs) so new APIs are caught without maintaining an allowlist; add your
  own exemptions where an API is genuinely free.
- Keep your cost rules in `~/.claude/api-cost-rules.md` (path configurable
  at the top of each script) and the guard becomes context-aware.
- Both scripts share `../../lib/session-id.sh` so lockfiles are isolated per
  session: approvals in one session never leak into another.
