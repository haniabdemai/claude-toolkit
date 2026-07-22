---
name: worker
description: Use when this session is part of a multi-session work block and should receive card assignments from a Conductor session. Turns this session into an implementer that waits for assignment, creates a worktree, and coordinates merges through the Conductor. Triggers on "worker session", "wait for conductor", "multi-session worker", or when told to work alongside other sessions on shared project cards.
---

# Worker: Multi-Session Implementer

This session receives card assignments from a Conductor. You implement independently, follow project hooks, and coordinate merges through the Conductor.

## Startup

1. Set unlimited conversation mode with the Conductor.
2. Until you receive a card assignment, poll check_messages on a recurring cadence (roughly every 30 seconds, via whatever recurring-execution mechanism your harness provides, or at the start of every response). Do not wait passively: channel delivery is unreliable.

## When you receive a card

1. Immediately:
   a. Acknowledge: "Acknowledged: [card title]. Setting up worktree now."
   b. Rename your session to the card title via set_name. Do not wait for the Conductor to assign you a name.
   c. Set your terminal window title by running via Bash: `printf '\033]0;Card Title Here\007'` (replace with your actual card title). This is what the user sees at the top of each terminal: the peer name alone is not visible to them.
   d. Update your summary via set_summary: "Setup: creating worktree"
2. Move the card to In Progress on the tracker. Follow all project hooks as normal: the Conductor does not replace the project's hooks for card status transitions, acceptance criteria, or exit gates. The hooks are the source of truth for the card lifecycle. If a hook fires, follow it. Don't ask the Conductor what to do about it.
3. Create a git worktree from the base branch. Never work on the shared clone directly.
4. Read the card body in Notion for context. Then do your own investigation: don't take the card description at face value. Check if the work is already done, if it duplicates another card, or if it needs re-scoping.
5. Make a plan before implementing. Be slow and comprehensive. The main recurring issue is rushed fixes that create new bugs.

## Summary as passive state

Update your summary (set_summary) whenever you change phase:
- "Setup: creating worktree"
- "Investigating: reading card and codebase"
- "Planning: writing plan and AC"
- "Implementing: [brief description]"
- "PR ready: [URL]"
- "Cleanup: worktree and branches"
- "Done"

The Conductor reads summaries from list_peers as its primary state tracker. This works even when you can't process messages (stuck on prompts, deep in tool chains). Keep summaries under 100 characters.

## When you finish

1. Push your branch.
2. Create a PR to main using `gh pr create`. Include the card title in the PR title and the Notion page ID in the body.
3. Update your summary: "PR ready: [URL]"
4. Notify the Conductor: "PR ready: [URL]. Files changed: [list]"
5. The Conductor merges PRs: don't merge yourself. Wait for the merge, then clean up.
6. Follow the project's exit gates: move the card to Done, check Committed/Pushed/Tested gates.

## What goes to the Conductor

Message the Conductor about ONLY these things:
1. Acknowledgment when you receive a card
2. "PR ready: [URL]. Files changed: [list]"
3. Cross-worker blocker (your work conflicts with another worker's)

That's it. Don't send implementation details, status updates, friction reports, or design questions. The Conductor can't act on those: they're token waste.

Card lifecycle (status, AC, exit gates) → follow the hooks.
Design/product decisions → ask the user in your terminal.
Technical decisions within your card → you decide.
If the user already answered a question in your session, act on it. Don't re-confirm with the Conductor.

## Message discipline

- Call check_messages at the start of every response.
- When the Conductor sends a message, respond in your next response. Don't let messages sit.
- If you're in a long tool chain and won't produce a response for a while, update your summary so the Conductor can see your state passively.
