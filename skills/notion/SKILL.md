---
name: notion
description: Use when designing, building, editing, reviewing, or reasoning about anything in Notion: databases, properties, formulas, rollups, relations, automations, views, templates, buttons, webhooks, or workspace architecture. Notion Formulas 2.0 (shipped 2024) fundamentally changed what's possible; by default LLMs reach for 1.0-shaped patterns (helper rollups, Is-Done flags, automations doing work a live formula could hold) even when they write 2.0 syntax. Also covers Notion buttons and webhook integrations, how to connect Notion to external services, trigger workflows, and sync data on demand. Load this skill proactively whenever Notion appears in the work, even if the user hasn't asked for formula help explicitly, including when they reference existing Notion pages, templates, workspaces, databases, buttons, webhooks, or just say "in Notion", "my template", "this database", "this page", "automation", "sync button", "trigger from Notion", or similar. This complements the Notion MCP (which handles API mechanics); this skill handles what Notion the product itself can do.
---

# Notion: capabilities, patterns, and design discipline

Notion shipped Formulas 2.0 in 2024. It changed what you should design, not just what you can type. The failure this skill exists to prevent: writing 2.0 *syntax* inside 1.0-shaped *architecture*. If you create helper rollups, Is-Done-style flags, or automations that conditionally flip properties a live formula could hold: you've built 1.0 with newer tokens.

Primary reference (check for updates if this skill is older than a few months): https://www.notion.com/help/guides/new-formulas-whats-changed

## The shift that matters

Before 2.0, formulas returned only text, numbers, and booleans. Aggregating over related pages required rollups. Breaking logic into steps required helper properties. Automations did the work formulas couldn't.

After 2.0:

- Relation and person properties return **lists** you can `.filter()`, `.map()`, `.length()`, `.first()` over directly.
- You can read across relations inline: `prop("Parent").first().prop("Phase")`. No rollup required.
- `let` and `lets` hold local variables, so one formula can do multi-step computation without helper properties.
- Formulas can output dates, people, pages, and lists, not only strings.
- `style()` colours text and backgrounds; `match()` pattern-matches.

Operational consequence: most helper properties that exist to feed another formula can be deleted. Most aggregation rollups can be replaced by a relation filter. Most automations that mutate state based on a computed condition can be split: the condition moves into a formula, and a minimal automation fires when a derived boolean flips.

## Design process: work backwards, not forwards

When designing a Notion schema, or extending an existing one, resist the instinct to list properties first.

1. **Start with the question the card must answer.** "What should I do next?" "Is this event still worth deciding on?" "Is this goal on track?"
2. **Write the formula that answers it.** Using relation filters, date arithmetic, and `let` for intermediate values.
3. **Add only the input properties that formula actually reads.** No helpers.
4. **Decide whether anything needs to be *written* in response to state changes.** If so, use a minimal automation (one trigger, one filter, one action) that fires on a boolean or status derived from the formula.

This inverts the default reflex of sketching a property list first and computing later. Under 2.0 the ratio of formula-work to automation-work has shifted: formulas hold live state, automations touch shared reality (send notifications, flip status, write to other pages).

## 1.0 anti-patterns: recognise and refactor

When reviewing existing Notion, these shapes are 1.0 residue. Flag them rather than silently replicate them:

- **Helper formula feeding a rollup feeding a formula.** The canonical case: `Is Done` formula → `Subtasks Done` rollup → `Progress` formula. Three properties doing what one formula does inline via list filtering.
- **Intermediate rollup that only exists to feed one automation or formula.** e.g. a `Parent Phase` rollup so an automation can read `Trigger page . Parent Phase`. Replace with inline dot access if the automation editor accepts it (see gotchas).
- **Helper formulas named `X_Flag`, `X_Count`, `X_Total`.** Usually intermediate state that should be inlined with `let`.
- **Status-to-integer converters.** A formula returning 1 or 0 based on Status, purely to let a rollup sum it. 2.0 filters the list directly.
- **Automation doing conditional mutation that a formula could express.** "When A is done AND B is empty, set C to true". If the condition is pure computation, the formula should hold it; the automation should only fire on the boolean output crossing a threshold.

The refactor move is the same in every case: collapse the chain into one formula on the source page, delete the helpers.

## Decision tree: when to use what

Given a requirement, pick the right tool. Default is formula first.

- **Compute a value from this page's own or its related pages' properties** → formula.
- **Aggregate across a relation (count, sum, average, any-match, all-match)** → formula with `.filter()` / `.length()` / `.map()`. Not a rollup.
- **Aggregate across non-relational, workspace-wide data (e.g. a count summary on a parent page)** → rollup or view summary. This is the narrow remaining case for rollups.
- **Write a value to a property in response to a state change** → automation. One trigger, one filter, one action.
- **Write a value based on a computed condition** → formula holds the condition; automation watches the boolean/status the formula flips; automation writes the side effect.
- **Show/hide pages based on state** → view filter. Not an automation. Not a property.
- **Visually signal urgency, stagnation, or state on the card face** → formula with `style()`. Notion does not support formula-driven *conditional card background colour* (see hard limits), but styled text inside a formula output is fully supported and renders on the card.

When in doubt: formula first.

## Capability reference

**Lists on relations and people.**
`prop("Relation Name")` returns a list of related pages. Chain list operations: `.filter(current.prop("X") == Y)`, `.map(current.prop("Name"))`, `.length()`, `.first()`. Inside `.filter()` / `.map()`, `current` is the related page; access its properties via `current.prop("Property Name")`.

**Cross-relation property access.**
`prop("Parent item").first().prop("Phase")` reads the parent page's Phase directly. No rollup required. On person and creator properties: `prop("Created By").name()` and `prop("Created By").email()`.

**Local variables: `let` and `lets`.**
```
let(subs, prop("Subtasks"),
  if(subs.length() > 0,
     subs.filter(current.prop("Status") == "Done").length() / subs.length(),
     0
  )
)
```
Three reasons to use `let`: readability, avoiding the paste-tokenisation bug (see gotchas), and multi-step computation without helper properties. `lets(a, expr1, b, expr2, ...)` for multiple bindings.

**Rich outputs.**
Formulas can return dates, pages, people, lists, not only strings. A formula returning a number renders with the number's format and visualisation (e.g. a bar). A formula returning a date is a date. A formula returning a list renders as chips.

**`style()` for colour.**
`style("text", "red")`, `style("text", "red_background")`. Concatenate multiple `style()` calls for different colours in one output. Platform supports 9 text colours and 9 background colours. Critical gotcha below about pipelines.

**`match()` for pattern matching.**
Regex-style string matching. Rarely useful: most Notion data is already structured.

**Multi-line editor with `#` comments.**
Formulas can span lines; `#` starts a comment. Use comments for non-obvious branches in longer formulas.

## Problem-shape patterns

**"Is this actionable right now?"**
Filter the `Depends On` relation for any predecessor whose Status isn't Done. Actionable = relation empty OR filtered list empty. Pair with `style()` for a green/locked badge on the card face. Sort board columns by this.

**"How stale is this?"**
`dateBetween(now(), lastEditedTime(), "days")`. Combined with a Support Needed / Stuck flag, surface avoided tasks. Threshold + `style()` puts the avoidance on the card face in red.

**"How urgent is this?"**
`dateBetween(prop("Date"), now(), "days")` returns a signed number. Bucket with nested `if` into today / this week / later, style each tier. Converts a static date into visible urgency.

**"Progress over related pages."**
`let(children, prop("Subtasks"), if(children.length() > 0, children.filter(current.prop("Status") == "Done").length() / children.length(), 0))`. Format as percent, show as a bar. No helper rollups.

**"Health / on-track signal."**
Compare (% of work done) vs (% of timeline elapsed, from start and end dates). If done lags elapsed by a threshold, show "behind" in red. Single formula.

**"Automation watching a formula's output."**
Automations **cannot trigger** on formula property changes directly. But formula properties **can** be used as filter conditions inside automations. The pattern:

1. Formula computes state continuously.
2. Automation triggers on a non-formula change (property edit, page created, scheduled).
3. Automation's filter checks the formula's value.
4. Automation writes a side effect.

Example: "When every dependency is Done AND Ready is unchecked, tick Ready and notify the assignee." The formula holds the dependency logic. The automation fires when any predecessor's Status changes, filters on the formula's boolean, writes the result.

This is how Formulas 2.0 makes automations smarter: formulas become the brain, automations become the hands.

## Operational gotchas

- **Formula editor save bug.** Full formula rewrites performed via browser automation (Playwright, DOM injection, AI text insertion in the editor) often fail to save silently: the formula appears in the editor, the preview works, but closing the dialog discards it. Small manual incremental edits in the Notion desktop app persist reliably. When a formula needs to change, ask the user to edit it in desktop Notion, not via automation. Verify "Edited just now" after each save.
- **`style()` is destroyed by `.split().filter().join()`.** A common pattern is building a card display as separator-joined segments, then piping through `.split("§").filter(current.length() > 0).join(" · ")` to drop empties. Styled output loses its colour inside that pipeline. Concatenate styled segments outside the pipeline, or use explicit `if(... + " · " ...)` concatenation when styling matters.
- **`"\n"` requires "Wrap cells" on the view.** Multi-line formula output only renders if the view has Wrap Cells enabled for that column. Silent failure otherwise.
- **3+ references to the same property can fail to tokenise on paste.** When pasting a formula with more than two references to the same `prop("X")`, some references sometimes collapse to untokenised text. Use `let` to bind once and reference the variable thereafter.
- **`month()` is 0-indexed.** January is 0, December is 11. For quarter calculation: `floor(month(d) / 3)`, not `floor((month(d) - 1) / 3)`.
- **Status-type property comparisons.** Comparing a Status-type property to a string may require `.name()` (`current.prop("Status").name() == "Done"`) rather than direct `==`. Test experimentally: don't assume.
- **Automation formula editor is a restricted subset** of the property formula language. Dot access across relations may or may not be accepted inside automation formulas. Test on a throwaway automation before promising a schema cleanup that depends on it.

## Buttons and webhooks: connecting Notion to external services

Notion buttons with "Send webhook" actions are the only native mechanism for user-initiated outbound HTTP calls. Reach for this pattern whenever the user wants to click something in Notion and have something happen elsewhere: trigger a sync, kick off a workflow, push data to an external service, or add a manual "refresh now" button alongside a scheduled automation.

Key constraints that trip people up: Notion sends its own JSON body (you can't control it), so target APIs with strict body requirements need a bridge function. Notion's URL validator also blocks certain domains (`script.google.com` is silently rejected). Button blocks are invisible to the Notion API ("unsupported" type): configuration is UI-only.

**Read `references/buttons-and-webhooks.md`** for the full implementation guide: URL validation rules, the bridge pattern with Google Cloud Functions, deployment commands, security considerations, and common mistakes.

## Hard platform limits 2.0 does not fix

- **Conditional card background colour** supports only select, multi-select, checkbox, number, and date properties as sources. Formula properties are **not** supported. Workaround: use `style()` inside the Card Display formula to emit coloured text or background-styled badges: different architecture, same visual goal.
- **Automations cannot trigger on formula property changes.** They can filter by formula values, but the trigger itself must be on a non-formula property edit, a page creation, or a schedule.
- **Formulas cannot write.** They only compute. Any state mutation requires an automation or manual edit.

## Verification discipline

Some 2.0 behaviour is experimentally determined rather than documented. Before recommending a schema change based on unverified syntax:

1. Open a throwaway test card, or an existing sandbox page.
2. Write the formula fragment there.
3. Confirm three things: it saves ("Edited just now" appears), it produces the expected output, it doesn't silently return empty.
4. Only then propose the change in the real schema.

Never promise "this syntax works" without having seen it work on this specific workspace.

## Worked example: 1.0 to 2.0 refactor

This is the canonical transformation. Recognise this shape and refactor it whenever you see it.

**Before (1.0-shaped):** four properties to compute subtask progress.

- `Is Done`: formula: `if(prop("Status") == "Done", 1, 0)`
- `Subtasks Done`: rollup: Subtasks → Is Done → Sum
- `Subtasks Total`: rollup: Subtasks → Is Done → Count
- `Progress`: formula: `if(prop("Subtasks Total") > 0, round(prop("Subtasks Done") / prop("Subtasks Total") * 100) / 100, 0)`

**After (2.0-shaped):** one property.

- `Progress`: formula:
```
let(subs, prop("Subtasks"),
  if(subs.length() > 0,
    round(subs.filter(current.prop("Status") == "Done").length() / subs.length() * 100) / 100,
    0
  )
)
```

The other three properties are deleted. Four down to one. The migration order matters: rewrite the Progress formula first (the rollups become unreferenced but still exist), then delete the rollups, then delete the helper formula. Do this in the Notion desktop app manually: do not attempt via browser automation because of the save bug.

## Before proposing any Notion change

When this skill is loaded, hold this checklist in mind:

- Understand what the card needs to *say* before listing what properties it needs.
- Prefer one formula with `let` over multiple helper properties.
- Filter over relations directly; don't add a rollup unless you genuinely can't do the aggregation in the formula.
- Use automations for side effects only, not as a hidden computation layer.
- For any unverified 2.0 syntax (Status comparison form, dot access inside automation editors), test on a throwaway before recommending.
- When you see a 1.0 anti-pattern in existing Notion, name it explicitly: don't silently replicate it because "it's already there".
