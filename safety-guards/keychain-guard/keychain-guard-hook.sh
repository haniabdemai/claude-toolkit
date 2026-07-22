#!/bin/bash
# PreToolUse hook for Bash: blocks Keychain enumeration commands.
#
# WHY: `security dump-keychain` (and `security dump`) iterates every item in
# the keychain; each protected item can trigger a separate macOS GUI popup,
# cascading dozens of prompts at the user (real incident: a careless
# fallback branch ran `security dump`).
#
# Single-item lookups (`security find-generic-password -s <name> -w`) remain
# allowed — that is the documented, safe pattern.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    j = json.load(sys.stdin)
    print(j.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null)

[ -z "$CMD" ] && echo '{}' && exit 0

# Block keychain dump/enumeration invocations. Anchored to command position
# (start of line, or after ; & | $( or backtick) so prose mentions of the
# phrase inside commit messages or echoes do not false-positive.
if echo "$CMD" | grep -qE '(^|[;&|`]|\$\()[[:space:]]*(sudo[[:space:]]+)?security[[:space:]]+dump(-keychain|-trust-settings)?\b'; then
    cat <<'BLOCK'
BLOCKED: keychain enumeration.

`security dump*` iterates every keychain item and can fire a cascade of GUI
password prompts at the user. This is permanently banned.

Use a single-item lookup instead:
    security find-generic-password -s <service-name> -w

Keep your service names written down somewhere greppable,
and read that note instead of searching the keychain.
BLOCK
    exit 2
fi

echo '{}'
exit 0
