---
name: automated-pipeline-setup
description: Checklist for setting up or fixing automated workflows that run unattended: GitHub Actions crons, scheduled scripts, OAuth-based pipelines, Claude remote triggers, API-key-driven automations. Use this skill whenever you are creating, configuring, debugging, or fixing any automation that runs on a schedule or without user interaction, especially if it involves Google OAuth, API keys, refresh tokens, GitHub Actions, cron jobs, Claude remote triggers, or scheduled tasks. Also trigger when fixing a broken pipeline, renewing expired tokens, or hearing "the cron stopped working" / "the action is failing" / "it was working last week" / "it keeps creating duplicates". Even if the task seems simple, invoke this skill, the checklist catches the infrastructure failures that code-level fixes miss.
---

# Automated Pipeline Setup

Hard-won checklist for unattended automations. Every rule exists because its absence caused a real failure: see the post-mortem at the bottom.

## Before building

### Check existing pipelines

Read your registry of active automated pipelines: trigger IDs, schedules, what they do, how to manage them (keep one; ours is a single markdown note). Check whether:
- A pipeline already exists for this task (don't build a duplicate)
- The new pipeline conflicts with or overlaps an existing one
- The existing entry has troubleshooting notes relevant to what you're building

### Google OAuth (if applicable)

The OAuth consent screen in GCP needs to be in Production mode (published), not Testing. Testing mode expires refresh tokens after 7 days: the pipeline works perfectly for a week, then silently dies with `invalid_grant`. This isn't documented prominently by Google and is the single most common cause of "it was working and now it's not."

- Verify at: `console.cloud.google.com/apis/credentials/consent?project=<PROJECT_ID>`
- Status should say "Published" or "In production", not "Testing"
- For personal-use apps where you're the only user, publishing doesn't require Google's verification review

### API rate limits and costs

Before writing code that calls a paid API on a schedule, check your API cost notes for existing protections. If the API isn't documented there, flag it and research pricing/quota before proceeding.

When implementing rate limiting in the script, use explicit delays between calls and document the quota in a code comment so future editors know why the delay exists.

### Secrets and credentials

- Refresh tokens, API keys, and client secrets go in GitHub Secrets (or equivalent secure storage), never in code
- OAuth `client_secret.json` files: delete after use, never commit
- Document which secrets are required and where to regenerate them in the README

## While building

### Idempotency

Any script that creates resources (calendar events, database rows, notifications, files) on a schedule needs to be idempotent. If the script runs twice, the user should see the same result as if it ran once. Without this, you'll get duplicates accumulating daily, and the user will notice before you do.

**Tag-based dedup pattern:**
1. Embed a unique marker in created resources (e.g. `[auto-tag:ORIGINAL_ID]` in a description field)
2. Before creating, search for existing resources with that marker
3. If found, skip creation

**Common dedup failures to avoid:**
- **Scan window too narrow**: if your dedup search starts from "now", it misses items created earlier today. Start from midnight in the user's timezone, not UTC, not the current time
- **Pre-existing untagged data**: when adding dedup tags to a system that already has items from before tags existed, those old items are invisible to the tag search. Find and clean them up before deploying, or the old and new items will coexist as duplicates
- **Regex/format mismatch**: if the tag format has spaces, special characters, or IDs with underscores, the extraction regex needs to handle all variants. Test with real data from the API, not assumed formats

### End-to-end testing

After deploying, trigger the pipeline manually and watch it complete:

```bash
# GitHub Actions
gh workflow run <workflow>.yml --repo <owner>/<repo>
gh run list --repo <owner>/<repo> --limit 3
gh run view <run-id> --repo <owner>/<repo> --log

# Claude remote triggers (example specific to Claude's remote-trigger
# tooling; substitute your own scheduler's manual-run command)
# Use RemoteTrigger run <trigger-id>
```

A code fix that's committed but crashes at the infrastructure layer (auth, permissions, missing secrets) is not a fix. The test is a green run, not "the code looks right."

## Before declaring done

1. **Is the latest run green?** Check `gh run list` (Actions) or the trigger history (remote triggers). If the last N runs are red, the fix hasn't been verified
2. **Has the pipeline run end-to-end with the current code?** Not a previous version, not a local run: the actual deployed pipeline
3. **Are there leftover artifacts from before the fix?** Old duplicates, untagged items, stale data. If the fix prevents future problems but doesn't clean up existing ones, the user still sees the mess
4. **Is the failure mode documented?** If the pipeline can break silently (expired token, revoked permission), document symptoms and recovery steps in the README
5. **Is the OAuth consent screen published?** Double-check: this is worth verifying twice
6. **Is the pipeline registered?** Update the pipeline registry with: trigger ID/repo, schedule, purpose, secrets required, GCP project (if applicable), retirement condition, and troubleshooting notes. If a new API was introduced, update the API cost notes too

## Troubleshooting broken pipelines

When a pipeline that "was working" stops:

1. **Check run history first**: `gh run list --repo <owner>/<repo> --limit 10`. When did it start failing? The failure date often points to the cause
2. **Read the actual error**: `gh run view <id> --log`. Don't guess: read it
3. **Common causes by error type:**
   - `invalid_grant` / `Token has been expired or revoked` → OAuth consent screen likely reverted to Testing mode, or token was manually revoked. Fix: publish consent screen, re-run OAuth setup, update the secret
   - `403 Forbidden` / `insufficient permissions` → API was disabled or scope was reduced. Check GCP API dashboard
   - `quota exceeded` → check rate limits in your API cost notes
4. **After fixing, verify**: trigger a manual run and confirm it passes. Don't push the fix and walk away

## Why this checklist exists

In April 2026, a calendar leave reminder pipeline (GitHub Actions + Google Calendar API + Routes API) created 45+ duplicate reminders over 8 days because of compounding failures:

1. The OAuth consent screen was in Testing mode: the refresh token expired after 7 days and the pipeline silently died
2. The dedup regex didn't match the tag format (space vs no-space after a colon)
3. `time_min=now` in the dedup scan missed reminders created earlier the same day
4. The very first run (before tagging was added) created untagged reminders invisible to all subsequent dedup checks
5. A previous fix session committed correct code but never checked GitHub Actions: all 7 runs after the fix were failing at the auth layer, and the session declared "fixed"

Every rule in this checklist prevents one of these failures.
