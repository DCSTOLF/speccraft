---
id: "0031"
title: "TDD guard Write-tool red-candidate blind spot"
status: closed
created: 2026-07-24
revision: 1
authors: [claude]
packages: ["tools/cmd/speccraft-guard"]
related-specs: ["0012", "0018", "0030"]
reserves-specs: ["0032"]
---

# Spec 0031 — TDD guard Write-tool red-candidate blind spot

## Why

`speccraft-guard`'s red-check (spec 0018) requires an **observed failing**
just-added sibling test before it allows a Go/Python/JS-TS production edit. It
learns which tests a session just-added by parsing the write-tool payload in
`captureRedCandidates` → `applyEdit`. But that parser only understands the
**Edit** tool: it reads `tool_input.new_string`, and `applyEdit` treats an empty
`old_string` as "Write tool → `new_string` is the full post-edit content"
([main.go:374-381](../../tools/cmd/speccraft-guard/main.go)).

The **Write** tool does not send `new_string` — it sends `content`. The guard's
`ToolInput` struct has no `content` field, so a test file *created* (or
overwritten) with Write yields an empty post-edit content, extracts **zero**
test IDs, and records **zero** red-candidates. The subsequent production edit is
then blocked with "no failing test observed for …" even though a perfectly good
RED test exists on disk.

This was hit head-on while implementing spec 0030: three `/speccraft:spec:override`
were spent because the RED tests were authored with the Write tool and registered
no candidates. It stays invisible because the guard's own tests mis-simulate
Write — `captureCase`
([main_test.go:781-791](../../tools/cmd/speccraft-guard/main_test.go)) builds
`ToolInput{FilePath, NewString: newContent}` (comment: "OldString empty ⇒ Write
semantics: NewString is the whole post-edit file"), which is **not** the payload
the harness actually sends. The fixture encodes the same wrong assumption as the
bug, so the suite is green while the real path is broken.

**The root cause is that tool *identity* is inferred from payload *shape*
(`old_string == ""`).** `HookInput.ToolName` already carries the real tool name
(`"Write"` / `"Edit"`) — the hook forwards the full PreToolUse envelope via
`exec speccraft-guard pre-tool-use <<<"$INPUT"` and `main.go` decodes
`tool_name`. The fix must switch on that identity, not on field emptiness: plain
Go `string` fields cannot distinguish an *absent* JSON key from an *explicitly
empty* one, so an empty-content Write and an empty-`old_string` Edit are
otherwise indistinguishable.

## What

Model the post-edit content per the **tool name**, so a Write-authored test file
registers its red-candidates and computes its just-added set exactly as an
Edit-authored one would — and correct the fixtures so they exercise the real
harness payload.

- **Discriminate on `ToolName`, not payload shape.** Add
  `Content string \`json:"content"\`` to the guard's `ToolInput`. Replace the
  `old_string == ""` heuristic in the post-edit modeling with an explicit switch
  on the tool name (thread `HookInput.ToolName` into `applyEdit`, or resolve a
  discriminated edit-operation before calling it):
  - `Write` → post-edit content **is** `content` (including the empty string, for
    a legitimately empty file); `new_string` is ignored.
  - `Edit` → post-edit content is a single `old_string → new_string` replacement,
    **preserved even when `old_string` is empty** (an Edit is never
    reclassified as a Write by field emptiness).
  - Any other tool name (e.g. `MultiEdit`/`NotebookEdit` reaching this path) →
    post-edit content **equals the pre-edit content** (no modeled change), so the
    just-added set is empty and no red-candidates are captured. This is the
    conservative default that AC7 pins as the current MultiEdit/NotebookEdit
    behavior until reserved spec 0032 models their payloads.
  This flows through `captureRedCandidates` and `computeJustAddedForEdit`, both of
  which call `applyEdit`.
- **Fix the fixtures.** Correct `captureCase` (and any peer that fakes a Write via
  `new_string`) to send `ToolName: "Write"` + `Content`, matching the real
  harness, so the regression can never be masked again.
- **Preserve fail-closed semantics.** No change to the red-check *decision* logic
  (unresolved-runner fail-closed, deadline bound, sibling resolution, observed-
  failure requirement). Only the payload-parsing *input* changes.
- **Adjacent gated tools.** `MultiEdit` and `NotebookEdit` are gated
  (`GATED_TOOLS` in `hooks/pre-tool-use.sh`) but their payloads (`edits[]`,
  notebook cells) are likewise unmodeled — the identical fail-closed blind spot.
  Their *fix* is out of scope, but this spec gives them an explicit, tested
  disposition and reserves a follow-up (see AC7 / reserved spec 0032).

## Acceptance criteria

1. `applyEdit` (or the discriminated edit-operation feeding it) selects post-edit
   content by **tool name**, verified by unit cases:
   (a) `Write` + non-empty `content` → returns `content` (regardless of pre-edit
   content and of any `new_string` value — a populated `new_string` on a Write is
   ignored);
   (b) `Write` + empty `content` → returns the empty string;
   (c) `Edit` + non-empty `old_string` → returns
   `strings.Replace(pre, old_string, new_string, 1)`;
   (d) `Edit` + empty `old_string` → still performs the replacement (is **not**
   treated as a Write).

2. The Edit path is behaviorally unchanged from today for all existing Edit
   payloads (regression assertion over the current `applyEdit` Edit cases).

3. A full **Write** PreToolUse envelope —
   `HookInput{ToolName: "Write", ToolInput: {FilePath, Content}}` with
   `new_string` absent — that adds test functions to a test file records those
   test IDs as the file's red-candidates (`GetRedCandidates`), where the current
   code records none. Covered for **both** file *creation* (no pre-existing file)
   and *overwrite* (pre-existing file whose content is replaced), for Go and
   Python, with one JS/TS case as the representative of the shared JS/TS extractor
   (documented as such).

4. End-to-end via `processToolUse` with an injected fake runner, proving the
   spec-0030 scenario no longer needs an override — as **two ordered calls**
   against an active `in-progress` spec, with **no override provisioned**
   (`override_pending` unset throughout):
   - Call 1: a `Write` envelope for the sibling **test** file captures a specific
     canonical test ID as a red-candidate.
   - Call 2: an `Edit` envelope for the **production** file. The fake runner is
     invoked exactly once with that captured ID and returns
     `OutcomeAtLeastOneFailed` carrying a failed record **whose name is that same
     ID**; `processToolUse` returns nil (edit allowed).
   The test asserts the runner was invoked with the captured ID (not an override
   or another allow-branch producing the nil result). One case for Go, one for
   Python.

5. The guard's Write fixtures construct payloads with `ToolName: "Write"` +
   `content` (never `new_string` with an empty `old_string`), proven by the
   corrected behavioral fixtures plus a narrow static check that no test helper
   builds a `Write`-labeled payload setting `NewString` without `Content`.

6. The version is bumped `1.7.0 → 1.7.1` (a guard behavior fix; patch) across the
   version surfaces (three `tools/cmd/*/main.go` consts +
   `.claude-plugin/{plugin,marketplace}.json`) with the sibling version-assertion
   tests updated, per the §Version bumps convention; "done" remains the published,
   self-verified release via the automated `auto-tag → release.yml →
   verify-release.sh` path when the bump lands on `main`.

7. `MultiEdit` and `NotebookEdit` get an explicit, tested disposition: a code
   comment + a test that pins their **current** behavior (a native `MultiEdit`
   `edits[]` / `NotebookEdit` payload captures **no** red-candidates today) so the
   known limitation is observable and a future fix is a deliberate change, and a
   reserved follow-up **spec 0032** is named for modeling their payloads. This
   spec does **not** fix MultiEdit/NotebookEdit.

## Out of scope

- **Fixing `MultiEdit`/`NotebookEdit` payload modeling** — dispositioned and
  tracked (AC7 + reserved spec 0032), not fixed here.
- **The compiled-language new-symbol bootstrap.** A brand-new Go symbol's test
  cannot compile until the symbol exists, so the runner reports
  `OutcomeBuildFailed`, which the guard correctly does **not** treat as a valid
  RED; a genuine first-symbol bootstrap still uses `/speccraft:spec:override`.
  Treating a build failure as RED would accept unrelated build breakage as a false
  RED and weaken the fail-closed guardrail — it is **not** in scope and is not a
  deferred maybe (see resolved open question below).
- Any change to the red-check *decision* logic (fail-closed, deadline, sibling
  resolution) — only payload parsing changes.

## Open questions

_none_ — both revision-0 open questions were resolved by the 2026-07-24
cross-model review: (1) build-failed-as-RED → firmly **out of scope** (it does not
establish an observed test failure and conflicts with the fail-closed RED
guardrail); (2) MultiEdit fold-in → **not folded**; dispositioned in AC7 and
tracked by reserved spec 0032.
