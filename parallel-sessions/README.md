# parallel-sessions

**Run several Claude Code sessions on the same project at once without
them destroying each other's work.**

One AI coding session is easy. The moment you run four of them against one
repository, every `git checkout` in one session silently switches the
branch under all the others, commits capture half-finished work that isn't
theirs, and merges race. This system exists because exactly that happened:
four concurrent sessions repeatedly clobbered each other's branches and
lost real commits before a protocol was forced into existence.

It has two layers that work together:

## 1. The orchestration protocol (skills)

- [**conductor**](conductor/SKILL.md): turns one session into the
  coordinator: it assigns tasks from a shared board, sequences merges so
  conflicting work never lands simultaneously, detects stuck workers by
  cycle counting, and tracks worker state through peer summaries.
- [**worker**](worker/SKILL.md): the counterpart: a session that receives
  one task, creates an isolated git worktree, implements independently,
  and coordinates its merge through the conductor. Its
  "summary-as-passive-state" pattern keeps coordination alive even when a
  worker is blocked on a permission prompt.

The protocol needs two external things, both pluggable: an
**inter-session messaging channel** (any peer-messaging MCP with
send/check/summary-style tools) and a **shared task board** (see
[claude-project-tracker](../claude-project-tracker/) for the board these were built
against, and how to map it to Jira/Linear).

These skills were built against
[claude-peers-mcp](https://github.com/louislva/claude-peers-mcp) by
louislva, which provides the messaging channel. Credit to that project
for the peer-messaging layer; any peer-messaging MCP with equivalent
tools (`set_name`, `list_peers`, `send_message`, `check_messages`)
works.

Install the skills by copying them into your skills directory:

```bash
cp -r parallel-sessions/conductor ~/.claude/skills/conductor
cp -r parallel-sessions/worker ~/.claude/skills/worker
```

## 2. The git guards (hooks)

- [**worktree-guard**](worktree-guard/): intercepts every git command:
  prompts on branch switches, blocks commit/push/merge/rebase when
  concurrent sessions are detected outside a worktree, and makes worktree
  removal PR-aware.
- [**unmerged-pr-guard**](unmerged-pr-guard/): leaving a worktree becomes
  a checkpoint: blocked while the branch has an open PR, full cleanup once
  it's merged, a warning if unpushed commits exist.

The guards are valuable alone (install just them if you ever run two
sessions); the skills turn multi-session work from risky to routine.
Install snippets are on each hook's page.
