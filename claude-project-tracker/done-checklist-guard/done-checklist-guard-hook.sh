#!/bin/bash
# PreToolUse hook for mcp__claude_ai_Notion__notion-update-page | mcp__notion__API-patch-page
# Fires on Status changes to In Progress or Done.
# In Progress: non-blocking reminder (exit 0).
# Done: BLOCKS (exit 2) if the card has no acceptance criteria (to-do blocks).
# There is no Testing status, cards go straight from In Progress to Done.
# Graceful degradation: falls back to non-blocking if the API call fails.

INPUT=$(cat)

IFS='|' read -r STATUS PAGE_ID <<< "$(echo "$INPUT" | python3 -c "
import sys, json, re

def status_name(raw):
    # claude.ai Notion sends a flat string; the official Notion MCP sends
    # the API shape: {'select': {'name': ...}} or {'status': {'name': ...}}.
    if isinstance(raw, str):
        return raw
    if isinstance(raw, dict):
        for key in ('select', 'status'):
            inner = raw.get(key)
            if isinstance(inner, dict):
                return inner.get('name', '') or ''
    return ''

def page_uuid(raw):
    # Validate: accept only a hex UUID (dashed or not), normalised to
    # dashed form. Anything else (URLs, injection attempts) yields ''.
    m = re.search(r'[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', str(raw).lower())
    if not m:
        return ''
    h = m.group().replace('-', '')
    return f'{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}'

try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    props = ti.get('properties', {})
    print(status_name(props.get('Status', '')) + '|' + page_uuid(ti.get('page_id', '')))
except:
    print('|')
" 2>/dev/null)"

if [ "$STATUS" = "In Progress" ]; then
    cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"ACCEPTANCE CRITERIA GUARD: You are picking up this card. Before starting implementation, define acceptance criteria as a to-do checklist in the card's page body. Every criterion must be objective, specific, and verifiable DURING THIS SESSION.\n\nSTANDARD ITEMS (include on every code card):\n- [ ] Verified from user's perspective (open the app/page, see the change -- not just API responses)\n- [ ] Tested with real data, not just synthetic smoke tests\n- [ ] If data change: both storage AND presentation updated\n- [ ] Testing completed in this session (production is not a test environment)\n- [ ] Documentation updated if behaviour changed\n- [ ] Code committed and pushed to remote\n- [ ] If PR: merged to main, remote branch deleted, local branch cleaned up\n- [ ] No known issues shipped as 'minor' -- fix it or flag as blocker\n\nThen add CARD-SPECIFIC criteria for this card.\n\nDo NOT start implementation until the checklist is written on the card."}}
HOOK
elif [ "$STATUS" = "Done" ]; then
    # Verify acceptance-criteria to-do blocks exist on the card via the Notion
    # API. If the API call fails for any reason, degrade to non-blocking.
    BLOCKED=0

    if [ -n "$PAGE_ID" ]; then
        TOKEN="${NOTION_TOKEN:-$(security find-generic-password -s notion-api-key -w 2>/dev/null)}"
        if [ -n "$TOKEN" ]; then
            BLOCKS_JSON=$(curl -s --max-time 10 \
                -H "Authorization: Bearer $TOKEN" \
                -H "Notion-Version: 2022-06-28" \
                "https://api.notion.com/v1/blocks/${PAGE_ID}/children?page_size=100" 2>/dev/null)

            HAS_TODO=$(echo "$BLOCKS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('object') != 'list':
        print('error')
    else:
        blocks = data.get('results', [])
        todos = [b for b in blocks if b.get('type') == 'to_do']
        print('yes' if todos else 'no')
except:
    print('error')
" 2>/dev/null)

            if [ "$HAS_TODO" = "no" ]; then
                BLOCKED=1
            fi
        fi
    fi

    if [ "$BLOCKED" = "1" ]; then
        cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"BLOCKED: Cannot mark this card Done, no acceptance criteria found.\n\nEvery card marked Done must have to-do checkboxes in the page body that were defined BEFORE implementation and verified during testing.\n\nTo proceed:\n1. Go back and add acceptance criteria as to-do items in the card body.\n2. Verify each criterion against the actual user experience.\n3. Check off each item.\n4. Then mark Done again.\n\nThis is a hard requirement. Retroactive criteria that just describe what was built defeat the purpose, criteria should have guided the work."}}
HOOK
        exit 2
    fi

    cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"ACCEPTANCE CRITERIA GUARD: You are marking this card Done. Before proceeding:\n\n1. Open the card and read every acceptance criterion (to-do checkbox) in the page body.\n2. Verify each one, open the page, run the query, check the output. Not API responses, the actual user experience.\n3. Check off each criterion as you verify it.\n4. If ANY criterion is not met, this is NOT Done.\n\nDo NOT downgrade unmet criteria to 'known minor'. Do NOT mark Done with unchecked items."}}
HOOK
fi

exit 0
