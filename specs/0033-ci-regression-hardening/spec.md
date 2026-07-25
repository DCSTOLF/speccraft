---
id: "0033"
title: "Post-0030/0031 CI regression hardening"
status: closed
created: 2026-07-24
revision: 1
authors: [claude]
packages: ["tools/internal/speccraft", "tests/e2e"]
related-specs: ["0029", "0030", "0031"]
---

<!-- ID allocation: 0032 remains RESERVED by spec 0031 (reserves-specs: ["0032"],
     for MultiEdit/NotebookEdit payload modeling). This spec intentionally skips it
     and takes 0033. It does NOT itself reserve 0032 — a reservation cannot name an
     ID lower than the reserving spec's own. -->


# Spec 0033 — Post-0030/0031 CI regression hardening

## Why

Shipping specs 0030 (1.7.0) and 0031 (1.7.1) surfaced three CI failures — two are
direct regressions from those specs (green locally in the Linux devcontainer, red
elsewhere), and one is a pre-existing consolidation-e2e flake bundled here because
it blocks the same gate. All three are test/fixture/prompt defects, not product
defects; the shipped behavior is correct.

- **(1) macOS-only Go test failure — spec 0030.**
  `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall` builds a fixture root
  via `newValidRoot` → `filepath.Abs(t.TempDir())` = `/var/folders/…`, but on
  macOS `/var` is a symlink to `/private/var`. The resolver *correctly* applies
  `filepath.EvalSymlinks` to the executable path (AC4 of spec 0030), yielding
  `/private/var/…`, so `got != want`. The code is right; the test's expected value
  is not `EvalSymlinks`-normalized. Passes on Linux (`/tmp` is not symlinked),
  fails on the macOS unit-test job.

- **(2) `rust_integration_cycle.sh` regression — spec 0031 (poetic).**
  The fixture sends a `{"tool_name":"Write"}` payload carrying the file content in
  `new_string` (with `old_string:""`) — the *exact* Write mis-simulation that spec
  0031 fixed in `captureCase`. Spec 0031's `applyEdit` now correctly reads
  `content` for a Write; the fixture sets no `content`, so post-edit content is
  empty → no just-added test → the guard does not reject → the leg fails
  ("expected rejection from shim-only path"). Root gap: spec 0031's AC5 static
  guard scanned only Go test files, so a shell e2e fixture with the same bug
  slipped through.

- **(3) `spec_consolidate.sh [cons 1/3]` decline leg — pre-existing; independent CI-unblock item.**
  This is NOT a 0030/0031 regression — it is bundled here solely because it blocks
  the same required e2e lifecycle gate as (1) and (2); treat it as an independent
  consolidation-fixture stabilization amendment. The credit-gated model ran
  `/speccraft:sync`, produced a memory-audit report
  (P1–P4 proposals) plus a decline *description*, then stopped to ask for
  confirmation instead of writing `specs/0090-decline-source/consolidation-skip`.
  This is the propose-and-wait-vs-APPLY failure the spec-0029 convention warns
  about ("a credit-gated e2e leg must instruct the model to APPLY, not
  propose-and-wait"): the model conflated the approval-gated memory proposals with
  the mechanical decline action. In the historically flaky 0025→0027→0028→0029
  consolidation lineage; not caused by 0030/0031, but it blocks the same e2e gate.

## What

Fix the two regressions and the flaky leg, and add a recurrence guard for the
class that (2) exposed.

- **(1)** Make the symlink assertion `EvalSymlinks`-robust: compare `got` against
  the symlink-resolved fixture root (e.g. `filepath.EvalSymlinks(root)`), not the
  raw `filepath.Abs` path. Test-only change in
  `tools/internal/speccraft/pluginroot_test.go`.

- **(2)** Correct `tests/e2e/rust_integration_cycle.sh`'s Step-2 payload to the
  real Write shape — `"content": "<file content>"` — dropping the
  `old_string`/`new_string` fields. The fixture then models the same post-write
  content the harness's `cat >` put on disk, restoring the intended rejection.

- **Recurrence guard for the (2) class.** Add a check — extending spec 0031's AC5
  intent from Go fixtures to **shell e2e fixtures** — that no `tests/e2e/*.sh`
  builds a `tool_name`-`Write` payload that carries `new_string` (a Write must use
  `content`). Implement wherever it is cheapest and CI-visible (a bats/verify
  assertion or a Go test that scans the fixtures).

- **(3)** Make the `[cons 1/3]` decline leg prompt in `tests/e2e/spec_consolidate.sh`
  imperative per the spec-0029 convention: instruct the model to DECLINE by
  **writing the `consolidation-skip` marker** for 0090 (and NOT moving the
  directory), to do so **without asking for confirmation**, and to keep the
  memory-audit proposals separate from that mechanical action.

## Acceptance criteria

1. `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall` passes on a host
   where `t.TempDir()` sits under a symlinked path (macOS `/var`→`/private/var`).
   The assertion is **asymmetric**: normalize only the *expected* fixture root
   (`want = filepath.EvalSymlinks(root)`) and compare the resolver's `got` to it
   directly — `got` is NOT normalized in the test. This preserves spec 0030's AC4
   sensitivity: a resolver that stopped calling `EvalSymlinks` would return the
   un-normalized `/var/…` path and the test would still FAIL (normalizing both
   sides would mask exactly that regression).

2. `bash tests/e2e/rust_integration_cycle.sh` reaches "OK: rust_integration_cycle
   e2e passed": the Step-2 payload uses `content` (real Write shape), the guard
   sees the added integration test, and the shim-only path yields the expected
   "no failing test observed" rejection.

3. A recurrence guard, implemented as a **Go test** that structurally scans every
   `tests/e2e/*.sh`, fails if any constructs a `Write` payload (`tool_name` =
   `"Write"`) that carries `new_string` in the **same** JSON envelope/block. The
   invariant is unconditional: a `Write` `tool_input` must never contain
   `new_string` (even if `content` is also present) — a Write's content lives in
   `content`. The scan associates `tool_name` and the forbidden field within one
   constructed envelope (not a repo-wide proximity grep), and it runs in the
   normal `go test ./...` job so it is CI-visible. It passes on the corrected
   fixtures (green post-(2)).

4. The `[cons 1/3]` decline leg is verified at TWO layers. (a) Credit-free: a
   meta-test reads the LIVE decline prompt string in
   `tests/e2e/spec_consolidate.sh` and asserts it pins the three terminal
   actions — write the `0090` `consolidation-skip` marker, do NOT move the
   directory, and do NOT wait for confirmation — and keeps the memory-audit
   proposals separate. (b) Credit-gated (unchanged): the leg's existing
   post-condition still asserts `consolidation-skip` exists on `0090` and the
   directory is unmoved. The credit-free meta-test makes the wording requirement
   deterministic without a model run.

5. Regression scope is contained to exactly three permitted file classes — the Go
   test (`tools/internal/speccraft/pluginroot_test.go`), the e2e fixtures under
   `tests/e2e/` (`rust_integration_cycle.sh`, `spec_consolidate.sh`), and the new
   recurrence-guard Go test — plus no other file. `go test ./...` and the full
   `tests/hooks/*.bats` suite stay green, and no `.go` product source (guard/
   state/drift binaries), command doc, hook, or template changes.

## Out of scope

- Any change to product behavior in `speccraft-guard`, `speccraft-state`, or the
  `applyEdit`/`pluginroot` logic — 0030 and 0031 shipped correct; this spec only
  aligns tests/fixtures/prompts with them.
- MultiEdit/NotebookEdit payload modeling (reserved spec 0032).
- A deeper redesign of the consolidation e2e or the `/speccraft:sync` memory-audit
  vs consolidation interleaving — (3) is a targeted prompt-wording fix, not a
  re-architecture of the flaky lineage.
- A version bump. Stated positively: this change touches **no** shipped plugin
  binary, manifest, command doc, hook, or user-facing command/agent prompt — only
  a Go test, e2e shell fixtures, and a new test. The changed `[cons 1/3]` string
  is **test-driver input** inside `tests/e2e/`, not a user-facing prompt. The
  §Version bumps convention is triggered by shipped behavior/API changes; none
  occur here, so no `const version` bump.

## Open questions

_none_ — the sole revision-0 open question (recurrence-guard layer) was resolved
by the 2026-07-24 review: AC3 pins it to a **Go test** scanning `tests/e2e/*.sh`.
