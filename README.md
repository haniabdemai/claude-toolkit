# claude-toolkit

**Three working systems for making Claude Code safer and more disciplined:
each one built because a real failure demanded it.** This is not a grab-bag
of prompts and scripts: every directory below is a coherent product you can
adopt whole, with its own README explaining the problem it solves, the
incident that created it, and exactly how to install it.

| System | The problem it solves |
|---|---|
| [**parallel-sessions**](parallel-sessions/) | Run several Claude Code sessions on one project at once without them destroying each other's git work. An orchestration protocol (conductor + worker) plus the two git guards that make it safe. |
| [**claude-project-tracker**](claude-project-tracker/) | Stop "done" meaning "the model felt done". Hooks that enforce a task-board discipline: surface unfinished work at session start, pick up a task properly, define acceptance criteria before coding, and never close work without a verified checklist. |
| [**safety-guards**](safety-guards/) | Protect your wallet and your machine: a cost gate before batch API operations, a Keychain-enumeration block, and a config-file lock. Independent hooks: adopt any subset. |

Plus two standalone **skills** (instruction sets Claude Code loads for a
class of task):

| Skill | What it encodes |
|---|---|
| [automated-pipeline-setup](skills/automated-pipeline-setup/SKILL.md) | A checklist for anything that runs unattended: the OAuth testing-mode trap, dedup windows, idempotency, end-to-end verification. Distilled from a post-mortem of an automation that silently died and created 45 duplicate reminders |
| [notion](skills/notion/SKILL.md) | Notion Formulas 2.0 architecture: formula-first design, 1.0→2.0 anti-pattern refactors, operational gotchas, plus a buttons-and-webhooks guide |

## How the pieces fit

Hooks are shell scripts wired into Claude Code's `settings.json` that
intercept tool calls *before they run*: deterministic enforcement where
the model can't talk itself out of it. Skills are markdown instruction
sets dropped into `~/.claude/skills/`. The exit-code contract for every
hook: `0` = allow (optionally injecting a message), `2` = block with a
message the model must act on. `lib/session-id.sh` is a shared utility
that keys lockfiles per session so concurrent sessions never trip each
other's state.

Each system's README carries its exact install snippets. Skills install
with a copy:

```bash
cp -r skills/notion ~/.claude/skills/
```

## Status

Extracted July 2026 from a private toolkit in daily use. macOS-centric
where it touches the Keychain and process table; the patterns port.

## Licence

[MIT](LICENSE)
