---
spec: "0042-init-workspace"
title: "init --workspace: scaffold a workspace root"
date: 2026-07-29
reviewers: [codex, claude-p]
quorum: 1
verdict: changes-requested
generated: 2026-07-29T00:00:00Z
---

# Cross-model review — 0042-init-workspace

## codex

**Verdict:** changes-requested

Concerns:
- AC5 cannot be implemented unambiguously while the template strategy (Open Question 1) is open; dedicated workspace templates would contradict the stated commands-only scope.
- AC6 and AC7 conflict: `--force` overwrites "identically to plain init" while AC7 requires preserving `workspace.yml`; the per-file preserve/overwrite policy is undefined.
- AC3 does not define candidate ordering, approval granularity, symlink handling, hidden dirs, or serialization of child names containing spaces or `#`; output not deterministic.
- AC3's repo-kind test is ambiguous for missing/malformed `speccraft.toml` (`ReadConfig` coerces both to `kind=repo`); doesn't say whether a child must be a git repo or merely contain `.speccraft/`.
- Argument parsing under-specified: unknown flags, duplicate flags, positional args, updated argument-hint not defined.
- AC7 doesn't define behavior for an existing `speccraft.toml` with `repo` kind, malformed/duplicate kind, or existing `[tdd]` config; overlaps confusingly with the out-of-scope migration statement.
- AC8's byte-for-byte regression claim lacks a defined baseline/golden fixture and is stronger than the observable assertions; current init output includes user-authored + date-dependent content.
- No explicit deterministic test surface (bats) named for the new shell helpers.

Suggestions: (none explicitly separated by this reviewer — see concerns above, several of which imply concrete fixes)

Guardrail violations: none reported.

Convention violations:
- Sourceable command helpers must be pure colocated `commands/<name>.lib.sh` with bats coverage — not specified.
- Slash-command argument-hint must be accurate — `--workspace`/`--force` introduced without updating `init.md`'s `[--force]` hint.

## claude-p

**Verdict:** approve-with-comments

Concerns:
1. AC5 mixes structural and content signals — "describe a workspace-coordination root" is model-prose content, not a structural predicate (violates spec-0014). Needs a structural marker.
2. `workspace.yml` writer grammar under-specified (quoting, indentation, trailing newline, deep paths) — leaves AC7's "byte-preserves" without a canonical referent.
3. AC3 conflates deterministic detection (bats-tested helper) with model-driven prompting (credit-gated e2e); should split into AC3a/AC3b per tiering conventions.
4. Detection error handling unspecified for malformed/unreadable child `.speccraft/`, symlinked children, permission errors, hidden dotdirs.
5. AC8 "byte-for-byte unchanged" over-strong — narrow to a targeted grep (no `kind = workspace` line, no root `workspace.yml`).
6. AC7 idempotency silent on `speccraft.toml` preservation beyond the `kind` line.
7. Git-repo precondition for `--workspace` unstated.
8. `workspace.yml` at repo root (not `.speccraft/`) is unusual and not cross-referenced to where the Go reader expects it.

Suggestions: (none explicitly separated by this reviewer — see concerns above)

Guardrail violations: none reported.

Convention violations:
- spec-0014 structural-over-content (AC5).
- deterministic-seed-at-cheap-layer lineage (specs 0022/0024/0028) — AC3 untiered.

## Synthesis

The two reviews were produced independently but converge strongly on the same defects, which is a stronger signal than either alone. Both reviewers agree the spec is not yet ready for implementation as written: real ambiguities and one outright logical conflict block an unambiguous, deterministic implementation. Overall verdict: **changes-requested**.

Where the reviews overlap (high-confidence, must-fix):
- **AC6/AC7 conflict on `--force` semantics.** codex calls this out directly as a contradiction ("overwrites identically to plain init" vs. "byte-preserves workspace.yml"); claude-p independently flags that AC7 is silent on `speccraft.toml` preservation beyond the `kind` line and that the `workspace.yml` grammar underpinning "byte-preserves" is undefined. These are the same underlying gap: the spec needs an explicit per-file overwrite/preserve policy for `--force --workspace` re-runs, including the case where an existing root has `kind = repo` (which collides with the stated out-of-scope migration exclusion).
- **AC3 (member auto-detection) is underspecified for determinism.** codex lists missing ordering/approval-granularity/symlink/hidden-dir/name-escaping rules and an ambiguous repo-kind test for missing/malformed `speccraft.toml`; claude-p lists the same class of gaps (symlinked children, malformed/unreadable `.speccraft/`, permission errors, hidden dotdirs) and additionally flags that AC3 conflates a deterministic, bats-testable detection helper with a model-driven approval prompt that belongs in a credit-gated e2e tier. Both threads point to the same fix: tier AC3 into a deterministic detection sub-criterion (with fully specified edge-case rules) and a separate approval-flow sub-criterion.
- **AC8's "byte-for-byte unchanged" claim is over-strong.** Both reviewers independently flag this as unfalsifiable/untestable as stated — codex notes there's no golden fixture and current output has user-authored and date-dependent content; claude-p recommends narrowing the assertion to a targeted grep (absence of `kind = workspace` and no root `workspace.yml`) rather than full-output byte equality.
- **AC5's workspace-flavored seeding is under-determined**, compounded by the still-open template question (Open Question 1). codex notes AC5 can't be implemented unambiguously while the template strategy is undecided; claude-p adds that the current wording ("describe a workspace-coordination root") is content-level model prose rather than a structural predicate, violating the spec-0014 structural-over-content convention. Both point at the same root cause: AC5 needs either a resolved template decision or a structural marker that's independent of exact prose.

Additional points raised by only one reviewer but worth folding into the required-changes list because they identify concrete, testable gaps:
- Argument parsing is unspecified for unknown flags, duplicate flags, and positional args, and the command's argument-hint isn't updated for the new flags (codex).
- `workspace.yml` is written at the repo root rather than under `.speccraft/`, which is unusual and isn't cross-referenced against where the Go reader (`workspace_topology.go`) actually expects to find it (claude-p) — this should at minimum be confirmed against the existing reader contract before implementation.
- A git-repo precondition for `--workspace` is assumed but never stated (claude-p).

No guardrail violations were reported by either reviewer. Convention violations were reported by both and are listed above verbatim; the two named violations from codex (bare `.lib.sh` sourcing without bats coverage; stale argument-hint) and the two from claude-p (spec-0014 structural-over-content on AC5; untiered deterministic-seed on AC3) are independent findings, not duplicates, and both sets need addressing.

### Required changes (prioritized)

1. **Resolve the AC6/AC7 `--force` conflict.** Define, per file (`speccraft.toml`, `workspace.yml`, and the rest of the `.speccraft/` memory set), exactly what `--force --workspace` preserves vs. overwrites on a re-run — including the case where the existing root is `kind = repo` (clarify how this interacts with the stated out-of-scope in-place-migration exclusion) and cases of malformed/duplicate `kind` lines or existing `[tdd]` config.
2. **Fully specify AC3 (member auto-detection) and split it by tier.** Add a deterministic, bats-testable sub-criterion covering: candidate ordering, symlinked children, hidden directories, missing/malformed child `speccraft.toml` (today `ReadConfig` coerces both to `kind=repo` — state whether that's the intended detection signal or whether a git-repo check is also required), unreadable/permission-denied children, and serialization of child names containing spaces or `#`. Add a separate sub-criterion (credit-gated e2e tier) for the model-driven approval prompt itself, matching the deterministic-seed-at-cheap-layer convention (specs 0022/0024/0028).
3. **Narrow AC8's regression claim.** Replace "byte-for-byte unchanged" with a concrete, testable assertion — e.g., a targeted grep/diff against a defined golden fixture, or an explicit list of properties that must hold (no `kind = workspace` line, no `workspace.yml` written, existing file set unchanged) — that doesn't depend on user-authored or date-dependent content.
4. **Resolve AC5 against Open Question 1, and make the seeded-content requirement structural.** Either decide the template strategy (dedicated workspace template vs. post-copy edits) so AC5 is unambiguously implementable, and/or replace the "describe a workspace-coordination root" language with a structural predicate (e.g., a specific marker/section that must be present) per the spec-0014 structural-over-content convention.
5. **Specify `workspace.yml`'s grammar precisely enough to support "byte-preserves."** Nail down quoting, indentation, trailing newline, and deep-path handling so AC7's preserve claim has a canonical referent to preserve against.
6. **Confirm `workspace.yml`'s location against the Go reader's actual expectation.** Verify whether `workspace_topology.go` expects it at the repo root or under `.speccraft/`, and make the spec's stated location explicit and cross-referenced.
7. **Specify argument parsing and update the argument-hint.** Define behavior for unknown flags, duplicate flags, and stray positional args for `/speccraft:init --workspace [--force]`, and update `init.md`'s argument-hint to include `--workspace`.
8. **Address the two named convention violations directly:**
   - Ensure any new sourceable helper logic lives in `commands/init.lib.sh` as pure, colocated functions with bats coverage (not inline in `init.md`).
   - State the git-repo precondition for `--workspace` explicitly (what happens if run outside a git repo).

### Optional suggestions

- Consider whether AC2's "empty `members:` key + commented example" format should itself be pinned down with a byte-level fixture, now that AC7/AC8 are being tightened elsewhere in the spec — this would keep the whole artifact-writing surface consistently testable.
- Once AC3 is split (item 2 above), consider whether the existing step-8a test-root proposal flow it mirrors has any of these same edge cases already resolved in code — reusing that resolution (rather than re-deriving new rules) would keep the two proposal flows consistent.

## Next step

**Action:** Edit `spec.md` to address the required changes above (items 1–8), then re-review with `/speccraft:spec:review --diff` against this review to confirm the conflicts and ambiguities are resolved before moving to implementation planning.

---

## Round 2 — scoped `--diff` re-review (2026-07-29)

**Synthesized verdict: reviewed (quorum met).** claude-p: `approve-with-comments`; codex: `changes-requested` (single blocking item: the AC9 two-file-atomicity overclaim).

All eight required changes from round 1 were confirmed **RESOLVED** by both reviewers (template decision, per-file `--force` matrix, AC3a/AC3b split with full detection algorithm, structural AC5 marker, canonical `workspace.yml` shape, narrowed AC8, argument parsing + git precondition, named `init.lib.sh` helpers + bats coverage). Residual items, all folded into the final revision:

- **AC9 overclaim (codex, blocking):** reworded to the single invariant the write-ordering actually delivers — never a `kind = "workspace"` root without a companion manifest; the reverse residue (stray manifest under a repo-kind toml) is inert and reconciled on the next run. Two-file transactional atomicity is explicitly not claimed.
- **`ws_toml_body` vs duplicate-`kind` normalization (codex):** helper contract reworded — preserve a valid single-kind config, normalize duplicate/malformed `kind` to one line.
- **Argument parsing (both):** `ws_arg_parse` now covers duplicate flags (idempotent) + stray positional args; `argument-hint` update to `[--workspace] [--force]` recorded.
- **AC3b × AC6 (claude-p):** detection/approval skipped when an existing `workspace.yml` is preserved on `--force`.
- **AC7 precedence (claude-p):** migration refusal stated to take precedence over the AC6 `--force` matrix for a `kind = "repo"` root.

Spec promoted `draft → reviewed`. Next: `/speccraft:spec:plan`.
reviewed_sha256: 387f940decf247bfc564014dd184882977abb9b183e92e0a5fc861e110f627e6
