#!/bin/bash
# PostToolUse hook for mcp__claude_ai_Notion__notion-update-page | mcp__notion__API-patch-page
# When a card is moved to In Progress, automatically inserts the standard
# acceptance criteria checklist into the page body (if not already present).
# Also clears the card-edit-guard lockfile so Edit/Write is unblocked.

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

if [ "$STATUS" != "In Progress" ] || [ -z "$PAGE_ID" ]; then
    exit 0
fi

# Clear the card-edit-guard lockfile so Edit/Write is unblocked
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if source "${_HOOK_DIR}/../../lib/session-id.sh" 2>/dev/null; then
    SESSION_ID=$(get_session_id)
    if [ -n "$SESSION_ID" ]; then
        rm -f "${LOCKFILE_PREFIX}-${SESSION_ID}"
    fi
fi

TOKEN="${NOTION_TOKEN:-$(security find-generic-password -s notion-api-key -w 2>/dev/null)}"
if [ -z "$TOKEN" ]; then
    exit 0
fi

# Check if to-do blocks already exist (don't duplicate)
HAS_TODO=$(curl -s --max-time 10 \
    -H "Authorization: Bearer $TOKEN" \
    -H "Notion-Version: 2022-06-28" \
    "https://api.notion.com/v1/blocks/${PAGE_ID}/children?page_size=100" 2>/dev/null | python3 -c "
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

if [ "$HAS_TODO" != "no" ]; then
    # Already has to-do blocks, or API failed, don't touch
    exit 0
fi

# Insert standard acceptance criteria checklist
curl -s --max-time 10 \
    -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    "https://api.notion.com/v1/blocks/${PAGE_ID}/children" \
    -d '{
  "children": [
    {
      "object": "block",
      "type": "heading_2",
      "heading_2": {
        "rich_text": [{"type": "text", "text": {"content": "Acceptance Criteria"}}]
      }
    },
    {
      "object": "block",
      "type": "heading_3",
      "heading_3": {
        "rich_text": [{"type": "text", "text": {"content": "Standard"}}]
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "Verified from user'\''s perspective (open the app/page, see the change -- not just API responses)"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "Tested with real data, not just synthetic smoke tests"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "If data change: both storage AND presentation updated"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "Testing completed in this session (not deferred to production)"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "Documentation updated if behaviour changed"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "Code committed and pushed to remote"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "If PR: merged to main, remote branch deleted, local branch cleaned up"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": "No known issues shipped as minor -- fix it or flag as blocker"}}],
        "checked": false
      }
    },
    {
      "object": "block",
      "type": "heading_3",
      "heading_3": {
        "rich_text": [{"type": "text", "text": {"content": "Card-specific (add your own)"}}]
      }
    },
    {
      "object": "block",
      "type": "to_do",
      "to_do": {
        "rich_text": [{"type": "text", "text": {"content": ""}}],
        "checked": false
      }
    }
  ]
}' > /dev/null 2>&1

exit 0
