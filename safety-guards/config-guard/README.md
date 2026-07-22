# config-guard

*One of the independent [safety-guards](../): adopt it alone or with its siblings.*

**Purpose: protect the assistant's own configuration files from the
assistant.**

Claude Code's behaviour is defined by `settings.json`, `settings.local.json`
and `.claude.json`. If the assistant edits these directly and gets it wrong
mid-conversation: truncated JSON, a mangled hooks array, the damage is
recursive: the tool that would fix the config is the tool the broken config
just disabled. The incident behind this hook was exactly that: a failed
mid-conversation `settings` edit corrupted the config file.

These files also define the guardrails themselves, so "the assistant edits
its own guardrails freehand" is a category of change that should never
happen casually.

## What it does

- **Hard-blocks** (exit 2) any Edit or Write tool call targeting
  `.claude.json`, `settings.json`, or `settings.local.json` (matched by
  basename, so project- and user-level copies are both covered).
- The block message routes to the safe paths: `.claude.json` only via the
  `claude mcp` CLI (or a JSON-module one-liner that parses before writing);
  settings files only via a validated JSON round-trip, load the file with
  python3's `json` module, modify the parsed structure, and write it back
  only if it re-serialises cleanly. The message text is customisable: point
  it at your own safe editing path (a skill, a wrapper script) if you have
  one.

Exit codes: `0` allow, `2` block.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/safety-guards/config-guard/config-guard-hook.sh" }] }
    ]
  }
}
```

## Adapting it

The protected list is a one-line array at the top of the script: add any
file whose corruption would be self-amplifying (CI workflow files, deploy
manifests, the hooks themselves).
