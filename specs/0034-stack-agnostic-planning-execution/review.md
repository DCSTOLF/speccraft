# Review — 0034 Stack-agnostic planning & execution

Cross-model review, 2026-07-25. Two agents (agents.toml: codex, claude-p).

## Verdicts

| Agent | Verdict |
|-------|---------|
| codex | **changes-requested** |
| claude-p | **approve-with-comments** |

**Quorum (≥1 approve/approve-with-comments): MET** (claude-p). But both reviewers
converged independently on the same cluster of under-specified interface
contracts, so the synthesis recommends tightening §What/ACs before planning
rather than proceeding on the bare quorum.

No guardrail or convention violations flagged by either agent. Both affirm the
core design: keep the *shipped* template neutral while the *generated* host-repo
memory carries detected project-specific values — the right boundary, and AC7
promoting "templates stay stack-agnostic" from advisory to executable is called
out as a genuine improvement (spirit of 0033).

## Consolidated action items (convergent unless noted)

1. **Reconcile Rust (codex — blocker).** The Why cites `AdapterForLanguage`
   (which handles only go/python/js/ts) while the detection table + out-of-scope
   include Rust. Reality: Rust runs via a *separate* path — `runner.AdapterFor`
   (cargo/nextest, selected from `speccraft.toml`), not `AdapterForLanguage`.
   Both are "already-executed" paths. Fix the wording so Rust's existing
   configured runner/command is named and the inconsistency is gone.

2. **Pin the polyglot precedence order in §What (both).** AC2 tests "a fixed
   documented priority" but the order itself is absent. It's a public contract
   (host authors hit it). State the literal order + one-line justification; AC2
   then pins the *documented* order, with a boundary case per adjacent pair.

3. **Pin the conventions.md marker grammar (both — load-bearing for AC4+AC5).**
   Give the literal marker line, its regex, and one worked example. Define
   empty-value, malformed-marker, and duplicate-marker behavior (error vs empty
   vs detection-fallback). Include a test with a command containing quotes/shell
   operators.

4. **Define `detect-stack` output encoding (codex).** A versioned JSON object
   with explicit field names; `test_command` as raw command text; explicit
   exit-code behavior for the `unknown` stack.

5. **Typed patterns, not fake globs (codex).** Replace `test_glob` (a single
   string that can't hold `tests/*.rs (+ inline)` or `test_*.py`/`*_test.py`)
   with a `test_patterns` list; represent Rust inline tests as explicit metadata,
   not a filesystem glob.

6. **Make AC6's mechanical rule concrete (both).** "Mandate vs. example" is
   subjective. Adopt a rigid rule: any concrete language command in the four docs
   must sit in a fenced block that is *either* labeled `Example (<lang>):` *or*
   references `speccraft-state test-command`; the scanner flags a bare fenced
   `go test ./...` outside those two forms. Easier and less brittle than
   natural-language mandate-detection.

7. **Specify the init wiring + preserve-existing semantics (both).** `init.md`
   is the riskiest surface (neutral template meets host repo). State the
   mechanism (shell block → `detect-stack` → templated seed) AND that init
   **preserves** an existing `conventions.md` (it is the editable source of
   truth); add idempotency / existing-file-preservation / unknown-stack ACs.

8. **`detect-stack` outside repo root (both).** Specify detection examines only
   *exact repo-root* manifests; define behavior when run from a subdirectory
   (echoing spec 0030's `plugin-root` ambiguity-in-the-field lesson).

9. **Migration is opt-in (claude-p — note only).** Add a sentence that AC5's
   benefit is opt-in for already-initialized repos (re-init / manual edit); the
   1.8.0 upgrade does not auto-heal an existing Go-shaped `conventions.md`.

10. **Release-verify deferral (claude-p — note only).** State whether 0034
    inherits spec 0030 AC11's merge-time release-verify deferral or requires the
    tag→release→verify chain to complete before close.

## Recommendation

Design is correct and scope is disciplined; every action item is "pin the
string," not "rethink the approach." Apply items 1–8 to §What/ACs (and notes
9–10), then re-review — matching the 0030/0031 pattern where convergent
interface-contract gaps were tightened before planning.

---

## Round 2 — diff-focused re-review (revision 2), 2026-07-25

Spec revised to revision 2 addressing all 10 items. Both agents re-reviewed
diff-focused (pointed at their own concerns + asked for any regression).

| Agent | Round 1 | Round 2 |
|-------|---------|---------|
| codex | changes-requested | **approve-with-comments** |
| claude-p | approve-with-comments | **approve** |

**Quorum MET (approve + approve-with-comments).** Both confirmed every prior
concern resolved: Rust path reconciled (`AdapterFor`/`cfg.TDD.Rust.Runner` vs
`AdapterForLanguage`), typed `Stack` with `TestPatterns` list + `InlineTests`,
polyglot order `go > rust > python > ts > js` pinned at each adjacent boundary,
versioned `detect-stack` JSON + exit-code split (unknown=0, no-repo-root=nonzero),
marker grammar (empty/malformed→fallback, duplicate→first-wins, data-not-shell),
init preserve-existing idempotency, root-manifest-only detection, migration +
release-verify notes. No new material issues; no guardrail/convention violations.

Three convergent micro-suggestions from the reviewers were folded into revision 2
before marking reviewed (not deferred to planning):
- **Marker regex** → proper quoted-string body `((?:\\.|[^"\\])*)`, applied
  per-line (no cross-newline match); explicit `\"`/`\\` unescape rule. (codex +
  claude-p)
- **AC6 `example`-label** → pinned to regex `^\s*(#+\s*|>\s*)?example\b` so prose
  ending "…for example:" cannot admit a bare command block. (claude-p)
- **Migration note** → corrected the contradiction: init preserves an existing
  `conventions.md`, so an existing repo migrates only by manual edit/remove, NOT
  by re-init. (codex)

One reviewer suggestion **not** taken (documented): AC3 emitting *distinct* stderr
for "no repo root" vs "I/O error" — claude-p flagged it optional ("only if a
command-doc branch needs to disambiguate"); both non-zero is sufficient for the
current callers, so left out to avoid scope creep.

**Status → reviewed.** Next: `/speccraft:spec:plan`.
