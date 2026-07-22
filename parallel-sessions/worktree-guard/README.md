# worktree-guard

*Part of the [parallel-sessions](../) system for running multiple Claude Code sessions safely: see its README for the full picture.*

**Purpose: stop concurrent AI sessions from destroying each other's work in
a shared git clone.**

When several Claude Code sessions run against the same repository, every
`git checkout` from one session silently switches the branch under all of
them, and a commit or push can capture, or clobber, another session's
half-finished working tree. This is not hypothetical: the incident that
produced this hook lost commits and cross-contaminated branches across four
concurrent sessions until a coordination protocol was forced on them.

An instruction in a prompt ("please use worktrees") is advisory; the model
can forget it. A PreToolUse hook is not. This guard makes isolation the
default by intercepting every git command before it runs.

## What it does

Three tiers, applied to every Bash call that starts with `git`:

- **Always block, with a bypass path**: `checkout`/`switch` (branch
  changes affect every session sharing the clone) are denied outright;
  the block message explains how to proceed with a worktree or bypass
  with `WORKTREE_APPROVED=1`. `git worktree remove` is PR-aware: it
  hard-blocks removal while the branch has an open PR, performs full
  cleanup (worktree + local and remote branch) when the PR is merged, and
  allows with warnings otherwise.

  **Warning: this hook deletes local and remote branches when its
  conditions are met** (a merged PR on the branch being removed). Read
  the cleanup section of the script before installing if that concerns
  you.
- **Block when it matters**: `commit`, `push`, `merge`, `rebase`, `reset`
  are blocked (exit 2) only when concurrent sessions are detected (process
  table scan for other `claude` processes) **and** the session is not inside
  a worktree. `pull` and `fetch` stay exempt: they are read-only with
  respect to other sessions' work.
- **Everything else passes silently.**

The block message tells the session how to proceed: create a worktree, or
confirm with the other sessions and re-run with `WORKTREE_APPROVED=1`.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/parallel-sessions/worktree-guard/worktree-guard-hook.sh" }] }
    ]
  }
}
```

## Adapting it

- Session detection uses `ps -eo comm=` and counts `claude` processes:
  adjust the process name if your agent binary differs; the concurrency
  threshold is a one-line change.
- The `WORKTREE_APPROVED=1` escape hatch is a convention, not a secret:
  the point is that bypassing requires a deliberate, visible act.
