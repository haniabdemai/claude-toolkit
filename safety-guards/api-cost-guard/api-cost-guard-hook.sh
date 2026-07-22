#!/bin/bash
# PreToolUse hook for Bash: blocks batch API operations until scope is
# justified and user-approved. Generic detection — auto-scales to new APIs.
#
# Two-step flow:
#   1. First attempt: hook blocks (exit 2), shows five criteria to Claude.
#   2. Claude presents criteria to user, user approves.
#   3. Claude re-runs with SCOPE_APPROVED=1 — but the hook only accepts
#      this if a lockfile proves step 1 already fired this session.
#      Without the lockfile, SCOPE_APPROVED=1 is ignored and the block
#      fires again. This prevents Claude from skipping the first block.
#
# Lockfile is session-scoped (keyed by ancestor claude PID) and has a
# 1-hour TTL so stale files don't accumulate.

set -euo pipefail

# --- Session ID (reuses shared lib if available) ---
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
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    j = json.load(sys.stdin)
    print(j.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null)

# If empty command, let through
[ -z "$CMD" ] && echo '{}' && exit 0

# Notion API is free — exempt all calls unconditionally
echo "$CMD" | grep -qiE 'api\.notion\.com' && echo '{}' && exit 0

# Static analysis and syntax checks never call APIs, so exempt them
# (py_compile on a file whose name contains "migrate" is not a migration run)
echo "$CMD" | grep -qiE 'py_compile|bash -n |shellcheck|node --check|ruff (check|format)' && echo '{}' && exit 0

# Generic detection patterns
MATCH=0

# 1. Env var setting an API credential
echo "$CMD" | grep -qE '[A-Z_]+(API_KEY|TOKEN|SECRET)=' && MATCH=1

# 2. Batch/backfill script being EXECUTED — require an interpreter/exec prefix so
#    merely NAMING such a file (git add/commit, ls, cat) doesn't false-positive.
[ "$MATCH" -eq 0 ] && echo "$CMD" | grep -qiE '(python3?|bash|sh|uv run|\./)[^|&]*(backfill|batch|bulk|migrate)\S*\.(py|sh)' && MATCH=1

# 3. curl/wget to external API
[ "$MATCH" -eq 0 ] && echo "$CMD" | grep -qiE 'curl\s.*(https?://|api\.)' && MATCH=1

# 4. GitHub Actions workflow dispatch
[ "$MATCH" -eq 0 ] && echo "$CMD" | grep -qiE 'gh workflow run' && MATCH=1

# No match — let through silently
[ "$MATCH" -eq 0 ] && echo '{}' && exit 0

# --- API PATTERN MATCHED ---

# Clean up stale lockfiles (>1 hour old)
find "$LOCKDIR" -name "api-blocked-*" -mmin +60 -delete 2>/dev/null || true

# If SCOPE_APPROVED=1 is in the command, check the lockfile
LOCKFILE="$LOCKDIR/api-blocked-${SESSION_ID}"
if echo "$CMD" | grep -q 'SCOPE_APPROVED=1'; then
    if [ -f "$LOCKFILE" ]; then
        # The block fired previously this session — bypass is legitimate
        rm -f "$LOCKFILE"
        echo '{}' && exit 0
    fi
    # No lockfile = Claude tried to skip the first block. Fall through to BLOCKED.
fi

# --- BLOCKED ---
# Write lockfile so the NEXT attempt with SCOPE_APPROVED=1 can pass
touch "$LOCKFILE"

# Optional: keep your API cost rules (billing caps, approved services) in
# this file and the guard will include them in its prompt when present.
REF_FILE="$HOME/.claude/api-cost-rules.md"
REF_CONTENT=""
if [ -f "$REF_FILE" ]; then
    REF_CONTENT=$(cat "$REF_FILE")
fi

cat >&2 <<BLOCK
BLOCKED: API operation detected.

=== API COST REFERENCE ===
$REF_CONTENT
=== END REFERENCE ===

You may NOT proceed until ALL five criteria are met:

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

Once ALL five are met, re-run the command prepended with SCOPE_APPROVED=1
BLOCK

exit 2
