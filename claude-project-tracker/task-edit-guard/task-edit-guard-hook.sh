#!/bin/bash
# PreToolUse hook for Edit|Write
# Blocks code editing when a tracker card has been fetched at To Do/Backlog
# but not yet moved to In Progress. Cleared by acceptance-checklist-hook.sh.
#
# Fast path: if no lockfiles exist at all, exit immediately (~2ms).
# Session isolation: lockfiles keyed by ancestor claude PID via shared lib.
# Fail-open: any error in detection or file reading → exit 0.

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_HOOK_DIR}/../../lib/session-id.sh" 2>/dev/null || exit 0

# Fast path: no lockfiles exist
if ! ls ${LOCKFILE_PREFIX}-* >/dev/null 2>&1; then
    exit 0
fi

# Sweep: remove lockfiles where the PID is dead or no longer a claude process
for f in ${LOCKFILE_PREFIX}-*; do
    pid_suffix="${f##*-}"
    if [ -n "$pid_suffix" ]; then
        pid_comm=$(ps -o comm= -p "$pid_suffix" 2>/dev/null | xargs)
        if [ "$pid_comm" != "claude" ]; then
            rm -f "$f"
        fi
    fi
done
if ! ls ${LOCKFILE_PREFIX}-* >/dev/null 2>&1; then
    exit 0
fi

SESSION_ID=$(get_session_id)
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

LOCKFILE="${LOCKFILE_PREFIX}-${SESSION_ID}"

if [ ! -f "$LOCKFILE" ]; then
    exit 0
fi

# TTL: ignore lockfiles older than 4 hours (14400 seconds)
FILE_AGE=$(( $(date +%s) - $(stat -f %m "$LOCKFILE" 2>/dev/null || echo 0) ))
if [ "$FILE_AGE" -gt 14400 ] 2>/dev/null; then
    rm -f "$LOCKFILE"
    exit 0
fi

# Read card title, JSON-escaped for safe insertion into output
CARD_TITLE=$(_LOCKFILE="$LOCKFILE" python3 -c "
import json, os
try:
    with open(os.environ['_LOCKFILE']) as f:
        title = json.load(f).get('card_title', 'unknown')
    print(json.dumps(title)[1:-1])
except:
    print('unknown')
" 2>/dev/null)

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: You fetched tracker card \"${CARD_TITLE}\" but have not moved it to In Progress. Move the card to In Progress and write acceptance criteria before starting implementation.",
    "additionalContext": "CARD EDIT GUARD: You read a Project Tracker card at To Do but did not move it to In Progress. This is the #1 tracker workflow violation.\n\nTo unblock:\n1. Move the card to In Progress (notion-update-page with Status: In Progress)\n2. Write acceptance criteria as to-do checkboxes in the card body\n3. Then start coding\n\nTo dismiss (if you read the card by mistake and do not intend to work on it):\nRun via Bash: rm ${LOCKFILE}"
  }
}
JSON
exit 2
