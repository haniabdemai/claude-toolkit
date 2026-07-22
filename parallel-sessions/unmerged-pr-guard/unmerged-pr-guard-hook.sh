#!/bin/bash
# PreToolUse hook for ExitWorktree — guards worktree exit with PR-aware cleanup.
#
# Behaviour:
#   Open PR on branch    → BLOCK (exit 2) with peer coordination reminder
#   Merged PR on branch  → FULL CLEANUP (exit 2): remove worktree, delete local+remote branch
#   gh CLI fails         → WARN (exit 0) about auth, don't block
#   Unpushed commits     → WARN (exit 0) advisory about local-only work
#   On main/master       → PASS (exit 0)
#   Clean, no PR         → PASS (exit 0)

branch=$(git branch --show-current 2>/dev/null)
if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  exit 0
fi

# Single API call to check for open PRs
pr_json=$(gh pr list --head "$branch" --state open --json number,title --limit 1 2>/dev/null)
gh_exit=$?

if [ $gh_exit -ne 0 ]; then
  echo "WARNING: Could not verify PR status for branch '${branch}'." >&2
  echo "gh CLI failed (exit $gh_exit). Run 'gh auth status' to check." >&2
  exit 0
fi

# No open PR — check for merged PR (auto-cleanup) or unpushed commits
if [ "$pr_json" = "[]" ] || [ -z "$pr_json" ]; then

  # Check for merged PR — triggers full cleanup
  merged_json=$(gh pr list --head "$branch" --state merged --json number,title --limit 1 2>/dev/null)
  if [ $? -eq 0 ] && [ "$merged_json" != "[]" ] && [ -n "$merged_json" ]; then
    merged_num=$(printf '%s' "$merged_json" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['number'])" 2>/dev/null)
    merged_title=$(printf '%s' "$merged_json" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['title'])" 2>/dev/null)

    echo "PR #${merged_num:-?} (${merged_title:-unknown}) is merged. Running full cleanup..." >&2

    # Resolve paths: main repo from git-common-dir, current worktree path
    git_common=$(git rev-parse --git-common-dir 2>/dev/null)
    main_repo=$(cd "$git_common/.." 2>/dev/null && pwd -P)
    worktree_path=$(pwd -P)

    cleanup_ok=true

    # 1. Remove worktree (must run from main repo, not from inside the worktree)
    if [ -n "$main_repo" ] && [ "$main_repo" != "$worktree_path" ]; then
      if (cd "$main_repo" && git worktree remove "$worktree_path" 2>&1); then
        echo "  Worktree removed: $worktree_path" >&2
      else
        echo "  WARN: Could not remove worktree (may have uncommitted changes)" >&2
        cleanup_ok=false
      fi
    else
      echo "  WARN: Could not resolve main repo path, skipping worktree removal" >&2
      cleanup_ok=false
    fi

    # 2. Delete local branch (only possible after worktree is removed)
    if [ "$cleanup_ok" = true ]; then
      if (cd "$main_repo" && git branch -d "$branch" 2>&1); then
        echo "  Local branch deleted: $branch" >&2
      else
        echo "  WARN: Could not delete local branch '$branch'" >&2
      fi
    fi

    # 3. Delete remote branch
    if git push origin --delete "$branch" 2>/dev/null; then
      echo "  Remote branch deleted: origin/$branch" >&2
    else
      echo "  Remote branch already deleted or not found (OK)" >&2
    fi

    echo "" >&2
    echo "Cleanup complete for merged PR #${merged_num:-?}." >&2
    # Exit 2 to prevent ExitWorktree from running — cleanup is already done
    exit 2
  fi

  # No merged PR either — check for unpushed commits (advisory only)
  upstream=$(git rev-parse --abbrev-ref "@{u}" 2>/dev/null)
  if [ -z "$upstream" ]; then
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    default_branch="${default_branch:-main}"
    ahead=$(git rev-list --count "${default_branch}..HEAD" 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ] 2>/dev/null; then
      echo "NOTE: Branch '${branch}' has $ahead commit(s) not on main and no remote tracking branch." >&2
      echo "Consider: git push -u origin ${branch}" >&2
    fi
  else
    ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ] 2>/dev/null; then
      echo "NOTE: Branch '${branch}' has $ahead unpushed commit(s)." >&2
      echo "Consider: git push" >&2
    fi
  fi
  exit 0
fi

# Open PR found — extract details
pr_num=$(printf '%s' "$pr_json" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['number'])" 2>/dev/null)
pr_title=$(printf '%s' "$pr_json" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['title'])" 2>/dev/null)

echo "BLOCKED: PR #${pr_num:-?} (${pr_title:-unknown}) is still open on branch '${branch}'." >&2
echo "" >&2
echo "Before merging:" >&2
echo "  1. Check for active peers: list_peers" >&2
echo "  2. If peers found: message ALL of them and ask if they have pending work on main" >&2
echo "  3. WAIT for responses before merging" >&2
echo "" >&2
echo "Then merge (--delete-branch removes the remote branch):" >&2
echo "  gh pr merge ${pr_num:-UNKNOWN} --merge --delete-branch" >&2
echo "" >&2
echo "After merging: call ExitWorktree again to remove the local worktree and branch." >&2
echo "" >&2
echo "If merge is intentionally deferred, explain why to the user." >&2
exit 2
