#!/bin/bash
# PreToolUse hook for mcp__claude_ai_Notion__notion-fetch | mcp__notion__API-retrieve-a-page
# Fires when a session reads a Project Tracker card at To Do or Backlog.
# Injects a strong reminder to move to In Progress and write acceptance criteria.
# Non-blocking (exit 0) -- the session needs to read the card to understand it.
# Uses a cache file written by check-gates.py at session start (zero API overhead).
#
# Also writes a lockfile that task-edit-guard-hook.sh checks on Edit/Write.
# The lockfile is cleared by acceptance-checklist-hook.sh when the card moves to In Progress.

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_HOOK_DIR}/../../lib/session-id.sh" 2>/dev/null || exit 0

CACHE_FILE="/tmp/tracker-card-cache.json"

# No cache file = check-gates.py hasn't run yet. Skip silently.
if [ ! -f "$CACHE_FILE" ]; then
    exit 0
fi

INPUT=$(cat)

# Extract the page ID from tool_input.
# claude.ai Notion uses "id", official @notionhq/notion-mcp-server uses "page_id".
# The ID can be a URL or a UUID. Normalise to dashed UUID format.
PAGE_ID=$(echo "$INPUT" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    raw = ti.get('page_id', '') or ti.get('id', '')
    # Strip URL prefix if present -- extract the hex portion
    match = re.search(r'[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', raw.lower())
    if not match:
        print('')
    else:
        hex_id = match.group().replace('-', '')
        # Format as dashed UUID
        print(f'{hex_id[:8]}-{hex_id[8:12]}-{hex_id[12:16]}-{hex_id[16:20]}-{hex_id[20:]}')
except:
    print('')
" 2>/dev/null)

if [ -z "$PAGE_ID" ]; then
    exit 0
fi

# Look up the page ID in the cache. Returns status if found, empty if not a tracker card.
RESULT=$(python3 -c "
import sys, json
try:
    with open('$CACHE_FILE') as f:
        cache = json.load(f)
    card = cache.get('$PAGE_ID', {})
    status = card.get('status', '')
    title = card.get('title', '')
    if status:
        print(status + '|' + title)
    else:
        print('')
except:
    print('')
" 2>/dev/null)

if [ -z "$RESULT" ]; then
    # Not a tracker card. Exit silently.
    exit 0
fi

IFS='|' read -r CARD_STATUS CARD_TITLE <<< "$RESULT"

if [ "$CARD_STATUS" = "To Do" ] || [ "$CARD_STATUS" = "Backlog" ]; then
    SESSION_ID=$(get_session_id)
    if [ -n "$SESSION_ID" ]; then
        _CARD_TITLE="$CARD_TITLE" _PAGE_ID="$PAGE_ID" _LOCKFILE="${LOCKFILE_PREFIX}-${SESSION_ID}" python3 -c "
import json, os
with open(os.environ['_LOCKFILE'], 'w') as f:
    json.dump({'card_id': os.environ['_PAGE_ID'], 'card_title': os.environ['_CARD_TITLE']}, f)
" 2>/dev/null
    fi
    cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"CARD PICKUP GUARD: This is a tracker card at To Do. Before you start any implementation:\n\n1. MOVE this card to In Progress (this is not optional -- picking up a card IS moving it to In Progress).\n2. WRITE acceptance criteria as to-do checkboxes in the card body. Every criterion must be objective, specific, and verifiable DURING THIS SESSION -- not deferred to production.\n\nSTANDARD ITEMS (include on every code card):\n   - [ ] Verified from user's perspective (open the app/page, see the change -- not just API responses or data queries)\n   - [ ] Tested with real data, not just synthetic smoke tests\n   - [ ] If data change: both storage AND presentation updated (database value correct AND user sees the change)\n   - [ ] Testing completed in this session (production is not a test environment -- smoke tests, dry-runs, real data verification all count)\n   - [ ] Documentation updated if behaviour changed\n   - [ ] Code committed and pushed to remote\n   - [ ] If PR: merged to main, remote branch deleted, local branch cleaned up\n   - [ ] No known issues shipped as 'minor' -- either fix it or flag it as a blocker\n\nThen add CARD-SPECIFIC criteria -- what does done look like for THIS card specifically?\n\n3. ONLY THEN start implementation.\n\nYou cannot mark this card Done without acceptance criteria -- the Done hook will block you."}}
HOOK
fi

exit 0
