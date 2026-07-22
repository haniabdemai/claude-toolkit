# claude-project-tracker

**Make "done" mean something: a task-board discipline that Claude Code
physically cannot skip.**

Vocabulary first, because nothing here makes sense without it: work is
tracked as **cards on a task board**: one card per unit of work, each
with a **Status** (Backlog → To Do → In Progress → Done) and, in its body,
**acceptance criteria** written as checklist items. The reference board is
a Notion database: duplicate the ready-made
[live template](https://illustrious-othnielia-c26.notion.site/Claude-Project-Kanban-3a095c67143a81f59b35c15ad748b5ac),
and [tracker-template.md](tracker-template.md) documents its exact shape.

The problem: an AI session reads a task, dives straight into code, and
later declares "done", while the board still says To Do and no one ever
wrote down what done meant. **session-start-gate-check** opens each session
by listing what's unfinished and priming the cache the guards read; the four
guards below then close each gap in the loop, together forming a cycle with
no exit that skips verification:

```
 read a To Do card ──► task-pickup-guard   reminds: move it to In Progress,
        │                                  write acceptance criteria, and
        │                                  ARMS the enforcement
        ▼
 try to edit code ──► task-edit-guard      BLOCKS edits until the card
        │                                  actually moves to In Progress
        ▼
 card → In Progress ► acceptance-checklist inserts the standard acceptance
        │                                  criteria as checklist items,
        │                                  automatically
        ▼
 card → Done ───────► done-checklist-guard BLOCKS Done while the card has
                                           no checklist to verify against
```

- [**session-start-gate-check**](session-start-gate-check/): runs at session
  start; lists every card with an incomplete gate ("Done but not pushed", "no
  acceptance criteria") and writes the card cache the pickup guard reads.
  **Install this one first**: without its cache, task-pickup-guard silently
  no-ops.
- [**task-pickup-guard**](task-pickup-guard/): fires when a session reads
  a To Do/Backlog card; injects the pickup contract and arms enforcement.
- [**task-edit-guard**](task-edit-guard/): hard-blocks Edit/Write while a
  picked-up card hasn't moved. Tracker-agnostic (it only honours the
  lockfile the pickup guard writes).
- [**acceptance-checklist**](acceptance-checklist/): the automation that
  makes the gates satisfiable by default: In Progress → the standard
  criteria appear on the card, idempotently.
- [**done-checklist-guard**](done-checklist-guard/): no checklist, no
  Done.
- [**session-stamp**](session-stamp/): stamps the working session's id onto a
  card when it reaches In Progress, so a crashed session can be resumed
  (`claude --resume`). Optional, but turns the board into a recovery registry.

**Built for Notion** (the hooks match Notion MCP tools and call the Notion REST
API), and driven by your own coding agent, so there is **no Notion AI
subscription** and nothing "AI" running inside Notion. The underlying workflow
is a small four-operation contract that could be ported to another tracker with
some work (notes in [tracker-template.md](tracker-template.md) and on each hook's
page), but as shipped it is a Notion tool and we own that.

Works beautifully with [parallel-sessions](../parallel-sessions/): the
conductor assigns cards from the same board these hooks discipline.
