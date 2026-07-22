# unmerged-pr-guard

*Part of the [parallel-sessions](../) system for running multiple Claude Code sessions safely: see its README for the full picture.*

**Purpose: make "the work is merged" a precondition of leaving a worktree,
so branches never silently die with open PRs on them.**

The failure mode: a session finishes its implementation, creates a PR,
declares victory, and exits its worktree. The PR sits unmerged; the
worktree gets cleaned up; days later someone finds work that was "done"
but never landed. This guard turns worktree exit into a checkpoint where
the PR's real state is checked against reality.

## What it does

Intercepts the worktree-exit tool call and branches on the PR state of the
current branch (via `gh`):

| State | Behaviour |
|---|---|
| Open PR on branch | **Block** (exit 2): merge or close it first, coordinating with any other active sessions |
| PR merged | **Full cleanup**: removes the worktree and deletes the local and remote branch, so merged work leaves nothing behind |
| Unpushed commits | Warn (exit 0): advisory that local-only work exists |
| `gh` auth failure | Warn (exit 0): never blocks on tooling problems; fail-open |

**Warning: this hook deletes local and remote branches when its
conditions are met** (a merged PR on the current branch). Read the
cleanup section of the script before installing if that concerns you.

## Install

Wired to the tool your harness uses to leave a worktree (here, the
`ExitWorktree` tool):

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "ExitWorktree",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/parallel-sessions/unmerged-pr-guard/unmerged-pr-guard-hook.sh" }] }
    ]
  }
}
```

## Adapting it

- Requires an authenticated `gh` CLI.
- If your workflow has no dedicated exit tool, attach it to whatever marks
  the end of branch work (a `git worktree remove` matcher works: see
  worktree-guard, which implements exactly that PR-aware removal for the
  raw git command).
