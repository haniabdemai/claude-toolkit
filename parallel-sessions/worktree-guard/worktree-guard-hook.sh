#!/usr/bin/env bash
# PreToolUse hook: guards git operations when concurrent Claude Code
# sessions share a local clone.
#
# Tier A — always prompt: checkout (branch switch), switch, worktree
#          remove (blocks on open PR; auto-cleans on merged PR;
#          allows with warnings otherwise)
# Tier B — block when concurrent + not in worktree: commit, push,
#          merge, rebase, reset (pull and fetch are exempt — read-only)
# Tier C — always pass: everything else (status, log, diff, add,
#          branch, worktree add/list/prune, remote, fetch, tag, show,
#          stash, etc.)
#
# Detection: ps -eo comm= | grep -cw claude (pgrep -x doesn't work
# from within Claude Code's hook context on macOS).
# Worktree detection via git rev-parse.
# Fail-open: any detection error → exit 0 (never block on broken hook).
# Bypass: prepend WORKTREE_APPROVED=1 to the command after confirming
# via claude-peers that no other session shares this repo.
#
# Installed in: ~/.claude/settings.json → hooks.PreToolUse
# Matcher: Bash (no `if` filter — must fire on all Bash commands to
# catch compound commands like `cd /path && git commit`)

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Bypass: explicit approval after peer coordination
if echo "$CMD" | grep -q 'WORKTREE_APPROVED=1'; then
  exit 0
fi

# --- Tier A: branch-switching commands (always prompt) ---

is_branch_switch() {
  echo "$CMD" | grep -qE '(^|\s*&&\s*|\;\s*)git\s+(-[a-zA-Z]\s+)*checkout\b' ||
  echo "$CMD" | grep -qE '(^|\s*&&\s*|\;\s*)git\s+(-[a-zA-Z]\s+)*switch\b'
}

is_worktree_remove() {
  echo "$CMD" | grep -qE '(^|\s*&&\s*|\;\s*)git\s+worktree\s+remove\b'
}

is_checkout_exempt() {
  echo "$CMD" | grep -qE 'git\s+checkout\s+(--|HEAD\s*--)' && return 0
  echo "$CMD" | grep -qE 'git\s+checkout\s+-b\b' && return 0
  return 1
}

if is_branch_switch; then
  if is_checkout_exempt; then
    exit 0
  fi
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "git checkout/switch detected. Use 'git worktree add ../worktree-name branch' for isolated work. Prepend WORKTREE_APPROVED=1 if you are certain no other sessions share this clone.",
    "additionalContext": "WORKTREE GUARD: You are about to switch branches. If ANY other Claude Code session is working on this repo, git checkout will destroy their unstaged edits. Use 'git worktree add' instead. Bypass: prepend WORKTREE_APPROVED=1 after confirming via claude-peers."
  }
}
JSON
  exit 2
fi

if is_worktree_remove; then
  # PR-aware gate: allow removal when safe, block when PR is open.
  # This handles manually-created worktrees that ExitWorktree won't touch.
  # For merged PRs, does full cleanup (worktree + branches) matching
  # unmerged-pr-guard-hook.sh's ExitWorktree behavior.
  #
  # Known limitation: awk -v interprets C-style backslash escapes in
  # the path variable (\n, \t, etc). Paths with literal backslashes
  # would fail to match. This is extremely unlikely on Unix.

  # Extract cd target from compound commands (e.g. cd /repo && git worktree remove ../wt).
  # The hook's CWD differs from the command's target when cd hasn't executed yet.
  WT_RESOLVE_DIR=""
  if echo "$CMD" | grep -qE '(^|\s*&&\s*|\;\s*)cd\s+'; then
    WT_RESOLVE_DIR=$(echo "$CMD" | grep -oE '(^|\s*&&\s*|\;\s*)cd\s+[^ &;]+' | tail -1 | sed 's/.*cd[[:space:]]*//')
    WT_RESOLVE_DIR="${WT_RESOLVE_DIR/#\~/$HOME}"
  fi

  # Extract the worktree path: last non-flag argument after 'git worktree remove'
  WT_REMOVE_ARGS=$(echo "$CMD" | grep -oE 'git\s+worktree\s+remove\s+[^;&|><]+' \
    | sed 's/git[[:space:]]*worktree[[:space:]]*remove[[:space:]]*//')
  WT_PATH=$(echo "$WT_REMOVE_ARGS" | awk '{for(i=NF;i>=1;i--) if($i !~ /^-/) {print $i; exit}}')
  WT_PATH="${WT_PATH/#\~/$HOME}"
  if [ -n "$WT_PATH" ] && [ "${WT_PATH:0:1}" != "/" ]; then
    if [ -n "$WT_RESOLVE_DIR" ] && [ -d "$WT_RESOLVE_DIR" ]; then
      WT_PATH="$(cd "$WT_RESOLVE_DIR" && cd "$(dirname "$WT_PATH")" 2>/dev/null && pwd -P)/$(basename "$WT_PATH")" 2>/dev/null || true
    else
      WT_PATH="$(cd "$(dirname "$WT_PATH")" 2>/dev/null && pwd -P)/$(basename "$WT_PATH")" 2>/dev/null || true
    fi
  fi

  # Find the branch checked out in the target worktree (exact path match).
  # Run git from cd target or WT_PATH itself — hook CWD may not be a git repo.
  WT_GIT_DIR="${WT_RESOLVE_DIR:-$WT_PATH}"
  WT_BRANCH=""
  if [ -n "$WT_PATH" ]; then
    WT_BRANCH=$(git -C "$WT_GIT_DIR" worktree list 2>/dev/null \
      | awk -v path="$WT_PATH" '$1 == path' \
      | grep -oE '\[.*\]' | tr -d '[]')
  fi

  if [ -z "$WT_BRANCH" ] || [ "$WT_BRANCH" = "main" ] || [ "$WT_BRANCH" = "master" ]; then
    exit 0
  fi

  # Check for open PRs on this branch (run from git repo context)
  wt_pr_json=$(cd "$WT_GIT_DIR" && gh pr list --head "$WT_BRANCH" --state open --json number,title --limit 1 2>/dev/null)
  wt_gh_exit=$?

  if [ $wt_gh_exit -ne 0 ]; then
    echo "WARNING: Could not verify PR status for branch '${WT_BRANCH}'. Allowing removal." >&2
    exit 0
  fi

  if [ "$wt_pr_json" != "[]" ] && [ -n "$wt_pr_json" ]; then
    # Open PR — block with structured JSON (same format as branch-switch block)
    wt_pr_num=$(printf '%s' "$wt_pr_json" | jq -r '.[0].number // "?"' 2>/dev/null)
    wt_pr_title=$(printf '%s' "$wt_pr_json" | jq -r '.[0].title // "unknown"' 2>/dev/null)
    # JSON-escape before interpolating into the heredoc. PR titles are
    # attacker-controllable on a public repo and must never reach the JSON
    # output unescaped.
    wt_pr_num=$(_V="$wt_pr_num" python3 -c "import json, os; print(json.dumps(os.environ['_V'])[1:-1])" 2>/dev/null)
    wt_pr_title=$(_V="$wt_pr_title" python3 -c "import json, os; print(json.dumps(os.environ['_V'])[1:-1])" 2>/dev/null)
    cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: PR #${wt_pr_num} (${wt_pr_title}) is still open on branch '${WT_BRANCH}'.",
    "additionalContext": "WORKTREE GUARD: Before removing this worktree:\\n1. Check for active peers: list_peers\\n2. Merge the PR: gh pr merge ${wt_pr_num} --merge --delete-branch\\n3. Then retry: git worktree remove ${WT_PATH}"
  }
}
JSON
    exit 2
  fi

  # No open PR — check for unpushed commits before allowing removal.
  wt_upstream=$(git -C "$WT_GIT_DIR" rev-parse --verify "${WT_BRANCH}@{u}" 2>/dev/null)
  if [ -n "$wt_upstream" ]; then
    wt_ahead=$(git -C "$WT_GIT_DIR" rev-list --count "${WT_BRANCH}@{u}..${WT_BRANCH}" 2>/dev/null || echo "0")
    if [ "$wt_ahead" -gt 0 ]; then
      echo "WARNING: Branch '${WT_BRANCH}' has ${wt_ahead} unpushed commit(s)." >&2
      echo "  Consider: git push origin ${WT_BRANCH}" >&2
    fi
  else
    wt_default=$(git -C "$WT_GIT_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    wt_default="${wt_default:-main}"
    wt_ahead=$(git -C "$WT_GIT_DIR" rev-list --count "${wt_default}..${WT_BRANCH}" 2>/dev/null || echo "0")
    if [ "$wt_ahead" -gt 0 ]; then
      echo "WARNING: Branch '${WT_BRANCH}' has ${wt_ahead} commit(s) not on ${wt_default} and no remote tracking branch." >&2
      echo "  Consider: git push -u origin ${WT_BRANCH}" >&2
    fi
  fi

  # Check for merged PR — if found, do full cleanup (worktree + branches)
  # and block the original command (cleanup is already done).
  merged_json=$(cd "$WT_GIT_DIR" && gh pr list --head "$WT_BRANCH" --state merged --json number,title --limit 1 2>/dev/null)
  if [ $? -eq 0 ] && [ "$merged_json" != "[]" ] && [ -n "$merged_json" ]; then
    merged_num=$(printf '%s' "$merged_json" | jq -r '.[0].number // "?"' 2>/dev/null)
    merged_title=$(printf '%s' "$merged_json" | jq -r '.[0].title // "unknown"' 2>/dev/null)

    echo "PR #${merged_num} (${merged_title}) is merged. Running full cleanup..." >&2

    # Resolve main repo path for worktree removal.
    # git-common-dir may return a relative path — resolve from WT_GIT_DIR.
    wt_git_common=$(git -C "$WT_GIT_DIR" rev-parse --git-common-dir 2>/dev/null)
    wt_main_repo=$(cd "$WT_GIT_DIR" && cd "$wt_git_common/.." 2>/dev/null && pwd -P)

    wt_cleanup_ok=true
    if [ -n "$wt_main_repo" ] && [ "$wt_main_repo" != "$WT_PATH" ]; then
      if (cd "$wt_main_repo" && git worktree remove "$WT_PATH" 2>&1); then
        echo "  Worktree removed: $WT_PATH" >&2
      else
        echo "  WARN: Could not remove worktree (may have uncommitted changes)" >&2
        wt_cleanup_ok=false
      fi
    else
      echo "  WARN: Could not resolve main repo path, skipping worktree removal" >&2
      wt_cleanup_ok=false
    fi

    if [ "$wt_cleanup_ok" = true ]; then
      if (cd "$wt_main_repo" && git branch -d "$WT_BRANCH" 2>&1); then
        echo "  Local branch deleted: $WT_BRANCH" >&2
      else
        echo "  WARN: Could not delete local branch '$WT_BRANCH'" >&2
      fi
    fi

    if git -C "$wt_main_repo" push origin --delete "$WT_BRANCH" 2>/dev/null; then
      echo "  Remote branch deleted: origin/$WT_BRANCH" >&2
    else
      echo "  Remote branch already deleted or not found (OK)" >&2
    fi

    echo "" >&2
    echo "Cleanup complete for merged PR #${merged_num}." >&2
    # Block the original command — cleanup is already done
    exit 2
  fi

  # No PR at all — allow removal
  exit 0
fi

# --- Tier B: data-modifying commands (block when concurrent + shared clone) ---
# git pull and git fetch are exempt — they're read operations needed before
# creating a worktree. A fast-forward pull doesn't modify the working tree
# in a way that conflicts with other sessions.

is_data_modifying() {
  local has_git=0 has_modifier=0
  local token
  for token in $CMD; do
    case "$token" in
      git) has_git=1 ;;
      pull|fetch)
        # Only exempt standalone pull/fetch, not compound commands
        # that also contain modifiers (e.g., "git pull && git commit")
        ;;
      commit|push|merge|rebase|reset) has_modifier=1 ;;
    esac
  done
  # Only treat the command as data-modifying when it is actually a git
  # command. Without the has_git check, non-git commands containing these
  # words (e.g. "npm run reset") would be blocked.
  [ "$has_git" -eq 1 ] && [ "$has_modifier" -eq 1 ] && return 0
  return 1
}

if ! is_data_modifying; then
  exit 0
fi

# Check 1: Are we in a git worktree? If yes, we're isolated — safe.
# The hook's CWD may differ from the command's target directory (the
# cd in the command hasn't executed yet). Extract the cd target and
# check that directory instead.
CHECK_DIR=""
if echo "$CMD" | grep -qE '(^|\s*&&\s*|\;\s*)cd\s+'; then
  CHECK_DIR=$(echo "$CMD" | grep -oE '(^|\s*&&\s*|\;\s*)cd\s+[^ &;]+' | tail -1 | sed 's/.*cd[[:space:]]*//')
  CHECK_DIR="${CHECK_DIR/#\~/$HOME}"
fi
if [ -n "$CHECK_DIR" ] && [ -d "$CHECK_DIR" ]; then
  GIT_DIR=$(cd "$CHECK_DIR" && git rev-parse --git-dir 2>/dev/null) || true
  GIT_COMMON=$(cd "$CHECK_DIR" && git rev-parse --git-common-dir 2>/dev/null) || true
else
  GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || true
  GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || true
fi
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  exit 0
fi

# Check 2: Are there concurrent Claude Code CLI sessions?
# Uses ps instead of pgrep — pgrep -x doesn't work from within
# Claude Code's hook context on macOS (returns empty).
# grep -cw matches only the exact word "claude" (lowercase),
# ignoring "Claude" (Desktop app) and node processes.
SESSION_COUNT=$(ps -eo comm= 2>/dev/null | grep -cw claude)
if [ "$SESSION_COUNT" -le 1 ]; then
  exit 0
fi

# Both checks failed: shared clone + concurrent sessions. Block.
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: ${SESSION_COUNT} Claude Code sessions detected and you are NOT in a git worktree. Use 'git worktree add ../worktree-name branch' for isolation. Bypass: prepend WORKTREE_APPROVED=1 after confirming via claude-peers.",
    "additionalContext": "WORKTREE GUARD: ${SESSION_COUNT} concurrent Claude Code sessions detected and you are NOT in a git worktree. Committing/pushing from a shared clone risks overwriting another session's uncommitted work, and has caused real data loss. Either: (1) create a worktree with 'git worktree add ../worktree-name branch', or (2) prepend WORKTREE_APPROVED=1 after confirming via claude-peers that no other session shares this repo."
  }
}
JSON
exit 2
