#!/bin/bash
# PreToolUse hook for Agent: blocks agent dispatches that involve API
# operations until scope is justified and user-approved.
#
# Same two-step lockfile mechanism as api-cost-guard-hook.sh:
# First attempt blocks and creates lockfile. Second attempt with
# [SCOPE_APPROVED] only passes if lockfile exists (proving the block fired).

set -euo pipefail

# --- Session ID ---
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/session-id.sh"
if [ -f "$LIB" ]; then
    source "$LIB"
    SESSION_ID=$(get_session_id)
else
    SESSION_ID=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')
fi
LOCKDIR="/tmp/api-guard-locks"
mkdir -p "$LOCKDIR" 2>/dev/null || true

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    j = json.load(sys.stdin)
    print(j.get('tool_input', {}).get('prompt', ''))
except:
    print('')
" 2>/dev/null)

# If empty prompt, let through
[ -z "$PROMPT" ] && echo '{}' && exit 0

# Generic detection patterns against prompt text
MATCH=0

# 1. Sets an API credential env var (assignment, not a mere mention of the
#    name: prompts legitimately name env vars when describing config work)
echo "$PROMPT" | grep -qE '[A-Z_]+(API_KEY|TOKEN|SECRET)=' && MATCH=1

# 2. Describes an actual batch/backfill OPERATION. Bare words false-positive
#    on filenames and prose mentions, so require an operation verb next to
#    backfill/migration, or the batch/bulk operation bigrams.
[ "$MATCH" -eq 0 ] && echo "$PROMPT" | grep -qiE '((run|execute|perform|trigger|start|launch)[[:space:]]+(a[[:space:]]+|the[[:space:]]+)?[^[:space:]]*(backfill|migration)|(backfill|migrate)[[:space:]]+(all|every|each|the[[:space:]]+(entire|whole)|records|events|rows|database)|(batch|bulk)[- ]?(process|import|insert|update|delete|load|ingest|api|call|job|run))' && MATCH=1

# 3. Triggers a GitHub Actions workflow (running one, not merely naming the event)
[ "$MATCH" -eq 0 ] && echo "$PROMPT" | grep -qiE 'gh workflow run|/dispatches' && MATCH=1

# No match — let through silently
[ "$MATCH" -eq 0 ] && echo '{}' && exit 0

# --- API PATTERN MATCHED ---

# Clean up stale lockfiles
find "$LOCKDIR" -name "agent-api-blocked-*" -mmin +60 -delete 2>/dev/null || true

# If [SCOPE_APPROVED] is in the prompt, check the lockfile
LOCKFILE="$LOCKDIR/agent-api-blocked-${SESSION_ID}"
if echo "$PROMPT" | grep -q '\[SCOPE_APPROVED\]'; then
    if [ -f "$LOCKFILE" ]; then
        rm -f "$LOCKFILE"
        echo '{}' && exit 0
    fi
    # No lockfile = tried to skip the first block. Fall through.
fi

# --- BLOCKED ---
touch "$LOCKFILE"

# Optional: keep your API cost rules (billing caps, approved services) in
# this file and the guard will include them in its prompt when present.
REF_FILE="$HOME/.claude/api-cost-rules.md"
REF_CONTENT=""
if [ -f "$REF_FILE" ]; then
    REF_CONTENT=$(cat "$REF_FILE")
fi

cat >&2 <<BLOCK
BLOCKED: Agent dispatch involves API operations.

=== API COST REFERENCE ===
$REF_CONTENT
=== END REFERENCE ===

You may NOT dispatch this agent until ALL five criteria are met:

1. SCOPE JUSTIFIED: You have stated what data is relevant to this task
   and WHY only this subset matters.

2. EXCLUSIONS JUSTIFIED: You have stated what data is excluded and WHY
   it is irrelevant (past events, already-processed, specific verdicts, etc.).

3. ITEM COUNT CONFIRMED: You have stated the exact number of items that
   will be processed after scope and exclusions. A number, not "all eligible."

4. COST ESTIMATED AND JUSTIFIED: You have stated number of API calls ×
   cost per call = total, AND why this is reasonable relative to free
   tier/budget from the reference doc above.

5. USER HAS EXPLICITLY APPROVED: You have presented criteria 1-4 to the
   user and the user has said yes.

Once ALL five are met, re-dispatch with [SCOPE_APPROVED] in the prompt.
BLOCK

exit 2
