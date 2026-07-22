# safety-guards

**Three independent hooks that protect your wallet, your secrets, and the
assistant's own configuration.** Unlike the other systems in this repo,
these don't form a workflow: adopt any subset. What they share is the
philosophy: safety by construction, at the tool-call boundary, in
deterministic shell, not by hoping the model remembers to be careful.

- [**api-cost-guard**](api-cost-guard/): an AI assistant mid-task is one
  enthusiastic loop away from a real API bill. This guard intercepts
  batch-shaped operations against paid APIs (and the "do it in a subagent"
  loophole) and forces a two-step scope-and-cost justification the model
  cannot self-approve: the block must fire first, the user must approve,
  and only then does the approved re-run pass.
- [**keychain-guard**](keychain-guard/): blocks macOS Keychain
  *enumeration* (`security dump…`), which fires a cascade of GUI password
  prompts at whoever is at the machine, while keeping single-item lookups
  allowed. Draws the line between "read a credential" and "sweep them
  all".
- [**config-guard**](config-guard/): hard-blocks direct edits to
  `settings.json` / `.claude.json`: a failed mid-conversation config edit
  is recursive damage, because the broken config disables the tooling that
  would fix it. Routes changes to validated paths instead.

Install snippets and the full story behind each are on the individual
pages. Exit-code contract: `0` allow, `2` block with an actionable
message.

Note: hook state (lockfiles for the two-step approval flow) lives under
`/tmp` and assumes a single-user machine; on a shared host, another user
could read or pre-create those files.
