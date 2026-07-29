# Review — Spec 0038 Conductor primitives: ledger.md + reconcile rollup

Date: 2026-07-28 · Agents: codex, claude-p (quorum 1) · **Verdict: approve**

## Review loop

- **Self-check (spec-critic):** `needs-work` → **pass** over 2 rounds. Round 1
  found 10 items (spec-ref format, first-colon split, `updated`/idempotency clock
  seam, grammar completeness, blocked-vs-closed precedence, resolver outcomes,
  output column, malformed exit, the get-status refactor's guard path, the
  "never the ledger" clarification). Round 2 confirmed all 10 + caught 2 follow-ups
  (the `updated` settable-field collision, the 3-way→2-way resolver adapter) — both
  fixed.
- **Cross-model:** `claude-p` → **approve-with-comments**; `codex` →
  **changes-requested → (after amend) approve**. Codex's 5 concerns were closed in
  one revision; a final re-review left a single narrow grammar gap (junk content
  between a `## design` heading and its first member), fixed with one grammar rule
  + one AC1 fixture row.

## Key items caught & fixed (ranked)

1. **cmd root/path contract** (codex) — pinned: `ledger-set`/`reconcile` resolve
   the workspace root via `FindWorkspaceRoot`, use `<root>/.speccraft/ledger.md`,
   and resolve each member via `filepath.Join(root, member.Path)`.
2. **Canonical writer serialization** (codex + claude-p) — fully specified (header,
   fixed field order, empty-field `key:` form, blank-line policy, final newline,
   preamble-not-preserved) + a golden-output test and a byte-stable
   parse→write→parse→write invariant.
3. **`nowFn` clock seam shape** (codex) — named: unexported `ledgerNow` var,
   `t.Cleanup`-restorable, not a `SetLedgerField` parameter; resolves the
   `updated`-vs-idempotency tension deterministically.
4. **Grammar edges** (both) — CRLF/BOM tolerance, spaceless `key:value`, empty
   design-id/member-path, non-`design` headings, and junk between a design heading
   and its first member all pinned as fixture rows.
5. **`updated` field collision** (self-check) — `updated` excluded from the
   settable set (conductor-managed); `ledger-set … updated` rejected.
6. **spec-ref** — stored verbatim, unresolvable ⇒ Blocked (no shape validation).

## Points of agreement

- **No guardrail or convention violations** at any round: single-writer rule honored
  (ledger is `history.md`-class on `AtomicWriteFile`), `parseFrontmatterBlock`
  single-entrypoint reused, run()-seam zero-override pattern.
- **Scope discipline clean** — no 0039 orchestration (command, decomposition,
  dispatch, validate phase) leaks in; the `blocked`-overlay read is a read-time
  aggregation rule, not a write-time transition.
- **Override budget sound** — one consolidated internal bootstrap; subcommands +
  the `get-status` refactor at zero override, **contingent on the plan-time
  sequencing obligation** (author the reconcile/ledger-set cmd RED before the
  get-status refactor edit), which the spec records and the plan must honor.

## Aux-config note (non-blocking)

`.speccraft/agents.toml` has codex `cmd` as `["codex","exec","--sandbox workspace-write"]`;
the `--sandbox workspace-write` single token errors on codex-cli 0.145.0 and only
worked because the delegator split it. Worth fixing to
`["codex","exec","--sandbox","workspace-write"]` in a follow-up.
