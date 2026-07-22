#!/bin/bash
# PreToolUse hook for Edit|Write — blocks edits to critical config files.
# .claude.json must only be modified via `claude mcp` CLI or `python3 -c` with json module.
# settings.json and settings.local.json must only be modified via a validated
# JSON round-trip (python3 json module: parse, modify, re-serialise).
#
# Exit codes: 0 = allow, 2 = block

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

BASENAME=$(basename "$FILE_PATH" 2>/dev/null)

case "$BASENAME" in
  .claude.json)
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":"block","reason":"BLOCKED: Never edit .claude.json with Edit/Write. Use `claude mcp add/remove` for MCP changes, or `python3 -c` with json module for programmatic edits. Manual editing of this file has caused real data loss."}}'
    exit 2
    ;;
  settings.json|settings.local.json)
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":"block","reason":"BLOCKED: Never edit settings.json or settings.local.json with Edit/Write. Use a validated JSON round-trip instead: load the file with python3 and its json module, modify the parsed structure, and write it back only if it re-serialises cleanly. Customise this message to point at your own safe editing path if you have one."}}'
    exit 2
    ;;
esac

exit 0
