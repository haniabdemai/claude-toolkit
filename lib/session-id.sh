#!/bin/bash
# Shared utility for card pickup enforcement hooks.
# Sourced by: task-pickup-guard-hook.sh, task-edit-guard-hook.sh, acceptance-checklist-hook.sh
#
# Provides get_session_id() and lockfile path constants.

LOCKFILE_PREFIX="/tmp/card-pickup-blocked"

get_session_id() {
    local pid=$$
    local max_depth=15
    local depth=0
    while [ "$pid" != "1" ] && [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$depth" -lt "$max_depth" ]; do
        local cmd=$(ps -o comm= -p "$pid" 2>/dev/null | xargs)
        if [ "$cmd" = "claude" ]; then
            echo "$pid"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        depth=$((depth + 1))
    done
    return 1
}
