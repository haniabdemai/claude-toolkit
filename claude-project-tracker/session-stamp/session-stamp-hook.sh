#!/bin/bash
# PostToolUse hook for a Notion card update (e.g. mcp__notion__API-patch-page).
# When a card is moved to In Progress, stamps the card with the session's
# resume identity: "Session ID" (rich_text) + "Session Started" (date).
#
# Purpose: crash recovery. After an unexpected reboot/crash, the card shows
# which session was working it, so you can resume with:
#     cd <dir> && claude --resume <session id>
# Uses the session UUID from the hook input (a PID would die with the process;
# the UUID is what `--resume` accepts).
#
# Zero-token: the hook writes the properties itself; the model does nothing.
# Fail-open: a non-tracker page that gets Status="In Progress" simply lacks
# these properties, so the PATCH 400s harmlessly and nothing is written.
#
# Token: reads NOTION_TOKEN, else the macOS Keychain item `notion-api-key`.
# Change the get_token block for your own secret store.

INPUT=$(cat)

IFS='|' read -r STATUS PAGE_ID SESSION_UUID <<< "$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    props = ti.get('properties', {})
    print(props.get('Status', '') + '|' + ti.get('page_id', '') + '|' + d.get('session_id', ''))
except Exception:
    print('||')
" 2>/dev/null)"

if [ "$STATUS" != "In Progress" ] || [ -z "$PAGE_ID" ] || [ -z "$SESSION_UUID" ]; then
    exit 0
fi

TOKEN="${NOTION_TOKEN:-$(security find-generic-password -s notion-api-key -w 2>/dev/null)}"
if [ -z "$TOKEN" ]; then
    exit 0
fi

NOW=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds'))" 2>/dev/null)
CWD_NOTE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('cwd', ''))
except Exception:
    print('')
" 2>/dev/null)

# Build the JSON body with python3 json.dumps so SESSION_UUID and CWD_NOTE
# are properly escaped (paths can contain quotes, backslashes, etc.).
BODY=$(_UUID="$SESSION_UUID" _CWD="$CWD_NOTE" _NOW="$NOW" python3 -c "
import json, os
print(json.dumps({
    'properties': {
        'Session ID': {
            'rich_text': [{'type': 'text', 'text': {'content': os.environ['_UUID'] + ' @ ' + os.environ['_CWD']}}]
        },
        'Session Started': {
            'date': {'start': os.environ['_NOW']}
        }
    }
}))
" 2>/dev/null)
if [ -z "$BODY" ]; then
    exit 0
fi

curl -s --max-time 10 \
    -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    "https://api.notion.com/v1/pages/${PAGE_ID}" \
    -d "$BODY" > /dev/null 2>&1

exit 0
