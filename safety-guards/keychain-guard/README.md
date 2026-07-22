# keychain-guard

*One of the independent [safety-guards](../): adopt it alone or with its siblings.*

**Purpose: stop an AI assistant from enumerating the macOS Keychain, which
fires a cascade of GUI password prompts at whoever is sitting at the
machine.**

`security dump-keychain` iterates every item in the keychain, and each
protected item can raise its own macOS password dialog. The incident behind
this hook: a careless fallback branch in a script ran `security dump` and
the user was hit by a wall of sequential password prompts with no
explanation. To a user, that is indistinguishable from an attack.

The subtlety is that Keychain access itself must stay allowed: assistants
legitimately need single credentials. The line this hook draws is
*enumeration versus lookup*.

## What it does

- **Blocks** (exit 2) any Bash command matching Keychain enumeration
  (`security dump-keychain`, `security dump`, and friends).
- **Allows** the documented safe pattern: single-item lookups:

  ```bash
  security find-generic-password -s <service-name> -w
  ```

The block message teaches the safe pattern instead of just refusing, so the
assistant can self-correct in the same turn. Keep a plain-text note of your
service names somewhere greppable; looking up a name in a note costs
nothing, enumerating the keychain costs the user a prompt storm.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command",
                    "command": "bash /path/to/safety-guards/keychain-guard/keychain-guard-hook.sh" }] }
    ]
  }
}
```

## Adapting it

macOS-specific by nature. The pattern generalises to any secret store with
an expensive or noisy "list everything" operation (Windows Credential
Manager, `pass ls`, vault list endpoints): allow point reads, block sweeps.
