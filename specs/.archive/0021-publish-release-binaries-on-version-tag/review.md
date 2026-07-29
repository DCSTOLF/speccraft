---
spec: "0021"
title: "Publish release binaries on version tag"
revision: 2
reviewers: [codex, claude-p]
quorum: 1
verdict: reviewed
generated: 2026-06-18T00:00:00Z
---

# Cross-model review — 0021 (revision 2)

## codex (gpt-5.5)

**Verdict:** approve-with-comments

Concerns:
- Prior blockers substantively resolved, but the spec still does not explicitly name the CI credential profile for the auto-tag job, release-verification step, or optional main/scheduled guard.
- AC5's phrase "the bump cannot land released without the tag" is slightly imprecise: the main commit lands before the auto-tag job creates the tag. The intended invariant is that a main version bump must mechanically enqueue/create the matching tag.

Suggestions:
- Add one sentence stating that the auto-tag and release-verification jobs run in the cheap/non-Claude CI path and require only GITHUB_TOKEN, never ANTHROPIC_API_KEY.
- Tighten AC5 wording to say the bump cannot remain untagged after the main-push workflow succeeds.

Guardrail violations: none

Convention violations:
- Rule: CI job-split convention — new CI additions should declare tier and credential profile. Location: What item 3/4 and AC4/AC5.

---

## claude-p

**Verdict:** changes-requested

Concerns:
- BLOCKER (partially resolved): trigger event, pass/fail predicate, and deadlock-freedom are all present, but the credential profile the prior review explicitly demanded (GITHUB_TOKEN-only vs ANTHROPIC_API_KEY) is never named for the auto-tag job or the release-verify step/guard. The phrase "runs credit-free" in the AC preamble refers to the shell tests, not the CI jobs.
- LATENT CORRECTNESS FLAW (same root cause): GitHub Actions does NOT re-trigger workflows for tags pushed using the default GITHUB_TOKEN — this is an intentional loop guard. If the auto-tag job (What#3) pushes vX.Y.Z with the default token, release.yml's `on: push: tags: [v*]` will silently never fire. This breaks the AC5→release chain the entire automation rests on, in exactly the quiet way this spec exists to eliminate. The spec must specify the push mechanism (PAT, deploy key, or workflow_dispatch hand-off) or the "mechanical" release path is dead on arrival.
- The secondary (main/scheduled) guard in What#4 is left "optional" with no tier, trigger, or credential. If it ships it is a new CI job and inherits the same job-split declaration obligation.

Suggestions:
- Add one line to What#3/What#4 (or a Design decision) stating both new CI surfaces are GITHUB_TOKEN-only / cheap-hermetic tier and invoke no `claude -p`, satisfying the spec-0008 CI job-split convention explicitly.
- State the tag-push credential explicitly — e.g., "auto-tag pushes via a PAT or deploy key so release.yml's tag trigger fires" — and consider asserting this in CI run history as part of AC5's end-to-end observation.
- Minor: AC1's oracle says verify-release.sh asserts "the checksum verifies" — clarify whether it downloads a tarball to recompute the hash or only asserts checksums.txt resolves and lists all four names. Make the production invocation's scope explicit.

Guardrail violations: none

Convention violations:
- Rule: CI job-split convention (spec 0008) — new CI jobs must declare tier (cheap-hermetic vs credit-gated) and credential profile (GITHUB_TOKEN vs ANTHROPIC_API_KEY). Location: What#3 (auto-tag job) and What#4 / AC4 (release-verify step and secondary guard).

---

## Synthesis

### Quorum status

Quorum is met. codex voted approve-with-comments; claude-p voted changes-requested. Per the quorum rule (1 approve or approve-with-comments required), the spec advances to **reviewed** status and is cleared for planning. However, both agents converge on a shared set of items that must be addressed during planning or in a targeted spec touch-up before implementation begins. These are captured below as carry-forward items rather than re-review blockers.

### Resolved since revision 1

All eight items from the revision-1 review have been addressed:

1. AC4/AC5 ordering deadlock — resolved via the deadlock-free ordering invariant (main → auto-tag → release.yml) and the tag-keyed guard design.
2. Open Question 1 (automate tag creation) — resolved: What#3 specifies a main-push CI job that auto-creates the tag.
3. Open Question 2 (release guard tier and trigger) — resolved: primary guard is a final step inside release.yml (tag-keyed); secondary is explicitly optional.
4. doctor.sh state contract — resolved: .binary-provenance marker file specified in Design decisions.
5. Test/oracle strategy — resolved: shell tests via SPECCRAFT_RELEASE_BASE fixture for AC1–AC3; unit test for auto-tag logic for AC5; RED→GREEN wired into run_helper_unit_tests().
6. Complete-asset definition — resolved: exact four tarballs + checksums.txt enumerated; draft vs published distinction made explicit.
7. Open Question 3 (v1.0.0 backfill) — resolved as out-of-scope in the Out of scope section.
8. set -euo pipefail + curl interaction — resolved in Design decisions (explicit `if ! curl …` shape required).

---

## Must address during planning (carry-forward items)

These items do not block the reviewed verdict but are load-bearing enough that the implementer must resolve them before or during the planning phase. They should not be left to ad-hoc implementation choice.

### CF-1 (CORRECTNESS — highest priority): GitHub Actions tag-push token gotcha

GitHub Actions intentionally does not re-trigger `on: push: tags` workflows when the tag is pushed using the built-in `GITHUB_TOKEN`. If the auto-tag job (What#3) uses the default token to push `vX.Y.Z`, `release.yml` will silently never fire — breaking the entire automation chain this spec exists to create, with no visible error.

The planning task must specify the push mechanism explicitly. The three viable options are:

- A repository-scoped PAT stored as a secret, used by the auto-tag job for the `git push --tags` call.
- A deploy key with write access to refs, same usage.
- Skip the direct tag-push altogether and use a `workflow_dispatch` call (or `repository_dispatch`) to hand off to release.yml directly, avoiding the GITHUB_TOKEN trigger restriction entirely.

The chosen mechanism must be named in the implementation plan. Leaving it unspecified replicates the original silent-failure mode.

### CF-2 (CONVENTION): Declare CI tier and credential profile for both new CI surfaces

Per the spec-0008 CI job-split convention, every new CI job must declare its tier (cheap-hermetic vs credit-gated) and its credential profile (GITHUB_TOKEN-only vs ANTHROPIC_API_KEY required).

The spec describes two new CI surfaces — the auto-tag job (What#3) and the optional main/scheduled release-completeness guard (What#4) — without naming either property for either job. Both agents agree these are GITHUB_TOKEN-only, cheap-hermetic jobs that invoke no `claude -p`. That should be stated explicitly, either as an addendum to the Design decisions section or in the plan. If the secondary guard ships at all, it carries the same obligation.

### CF-3 (SPEC WORDING): Tighten AC5 phrasing

AC5 currently reads: "the bump cannot land 'released' without the tag." This is slightly imprecise: the main commit carrying the version bump always lands before the auto-tag job creates the tag (sequential CI). The intended invariant is that a merged version bump cannot remain untagged after the main-push workflow completes successfully. The plan (or a minor spec edit) should restate AC5 to use this formulation so the acceptance test has an unambiguous pass condition.

### CF-4 (MINOR CLARITY): verify-release.sh checksum-verification scope

AC1's oracle states verify-release.sh asserts "the checksum verifies" without distinguishing between two meaningfully different behaviors:

- **Weak form:** assert that checksums.txt resolves (HTTP 200) and lists all four expected tarball names.
- **Strong form:** download the host-platform tarball and recompute its hash against the value in checksums.txt.

The production invocation inside release.yml should state which form runs. The weak form is safe and fast for a CI post-upload check; the strong form provides deeper integrity assurance but takes more time. The plan should pick one and document it so the shell test fixture is scoped correctly.

---

**Action:** Proceed to planning. Before writing the implementation plan, resolve CF-1 (token mechanism for tag push) and CF-2 (CI tier + credential declarations) as explicit plan decisions. CF-3 and CF-4 can be addressed as minor spec edits inline with planning or as a single small pre-plan commit. No re-review is required.
