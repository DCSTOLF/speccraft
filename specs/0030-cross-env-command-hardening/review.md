---
spec: "0030-cross-env-command-hardening"
reviewers: [codex, claude-p, cross-reviewer-synthesis]
quorum: 1
verdict: approve-with-comments
rounds: 2
generated: 2026-07-24T00:00:00Z
---

# Cross-model review — 0030-cross-env-command-hardening

## Round 2 outcome (revision 1) — REVIEWED

Diff-focused re-review of revision 1 (which folded in the round-1 recommended
edits). Reviewers were asked to assess only whether the r0 blockers were
resolved and whether the revision introduced regressions.

- **codex:** `changes-requested` → narrowed to two residuals: (1) AC11's version
  bump must, per the release-completeness convention, produce the *published,
  verified* `vX.Y.Z` release, not just edited consts; (2) AC9's grep oracle
  wasn't fully pinned. Confirmed root-resolution, precedence, manifest identity,
  symlink policy, AC8/AC10, migration and convention-lockstep as **adequately
  resolved**.
- **claude-p:** `approve-with-comments` → "all 9 r0 blockers resolved with
  reproducible, testable criteria." Two non-blocking: the dogfood/stale-1.1.0
  cache burden (suggest exporting `SPECCRAFT_PLUGIN_ROOT` in `.devcontainer`),
  and AC9's list being a curated subset rather than the full RESERVED class
  (backstopped by AC8).

**Resolution (folded into revision 1, same file):**
- AC11 now references the automated `auto-tag → release.yml → verify-release.sh`
  path and defines "done" as the published+self-verified `v1.7.0` release
  (codex's cited convention verified against `.speccraft/conventions.md`
  §Version bumps — it is real and load-bearing).
- AC9 adds `pipestatus`, states the list is a curated high-risk subset, and
  names AC8's real-zsh source leg as the authoritative backstop for any miss.
- New AC12 exports `SPECCRAFT_PLUGIN_ROOT` in `.devcontainer` so dogfood
  sessions resolve to the working tree, not the stale cache.

**Quorum:** met (claude-p `approve-with-comments`); codex's two residuals were
substantive and are resolved in-text rather than deferred. Spec advanced to
`reviewed`. Convergence in 2 rounds (vs. the 4-round treadmill this spec's own
sibling improvement targets) — the diff-focused re-review brief kept round 2
scoped to deltas + regressions.

---

# Round 1 (revision 0) — the record below is retained for provenance

# Cross-model review — 0030-cross-env-command-hardening

## codex

**Verdict:** changes-requested

Concerns:
- AC1-2 define no deterministic resolution algorithm, source precedence, or root-validity test; could return an existing-but-incorrect parent, a stale persisted path, or a different version's root and still claim compliance.
- `os.Executable()` mechanism underspecified for symlinked launchers, PATH shims, copied/source-built test binaries, macOS path semantics, and layouts where the exe is not directly under `<root>/bin`. Must state whether to `EvalSymlinks` and how the candidate is validated.
- Multiple simultaneously installed plugin versions unaddressed: bare PATH lookup may select a different version than the command doc being executed, sourcing libs/templates from the wrong install.
- Persisting plugin root in project-local `state.json` is a poorly specified fallback (stale after upgrade, wrong version, unavailable before init, ambiguous in worktrees). OQ1 materially changes the design/tests and should be resolved before implementation.
- AC1's "dir containing `bin/`, `commands/`, `templates/`" is insufficient validation; requiring plugin-manifest identity (`.claude-plugin/plugin.json`) would make failure testable.
- AC3 doesn't define whether each command resolves once, how failure surfaces, or which syntactic forms count as a forbidden dereference (`${...}`, default expansions, concatenated, copied through a var).
- AC4 not reproducible: "first exported function" is undefined; shell functions aren't "exported"; many first functions need args/fixtures and may legitimately return non-zero. Conflates zsh identifier safety with functional success.
- AC5 gives no fixture, args, expected stdout/stderr, or exit status — not independently verifiable.
- AC6 ambiguous while OQ2 unresolved; "plain assigned shell variable" grammar omits `local`/`declare`/`typeset`, `read` targets, loop vars, array/indirect assignments; a naive grep matches comments/strings.
- grep-only reserved-name guard is fragile; should pin token/assignment grammar and complement with real-zsh execution cases for every renamed site.

Suggestions (implied by concerns above):
- Define an explicit resolution precedence and root-validity test for AC1/AC2.
- State the `EvalSymlinks` policy for `os.Executable()`.
- Add `.claude-plugin/plugin.json` manifest-identity validation to AC1.
- Rewrite AC4 to drop "exported"/"first function" language in favor of a reproducible test.
- Add a concrete fixture to AC5.
- Pin the AC6 identifier list and broaden/scope its assignment grammar.

Convention violation: the sourceable-command-helper convention documents `source "$CLAUDE_PLUGIN_ROOT/commands/<group>/<name>.lib.sh"`; changing all command bodies without updating that convention leaves canonical guidance contradictory.

Guardrail violations: none.

## claude-p

**Verdict:** approve-with-comments

Concerns:
- AC6 depends on OQ2 for verifiability — pin the authoritative zsh-reserved list in the spec or AC6 is not assertable.
- AC1 failure semantics underspecified — enumerate failure conditions.
- AC4 "first exported function" ambiguous.
- Dogfooding vs installed-layout asymmetry — claude-p's biggest single risk; the repo's self-hosted layout and the installed-plugin-cache layout can diverge and both need coverage.
- Precedence order between `CLAUDE_PLUGIN_ROOT` / `os.Executable()`-derived / persisted value unspecified; the conflict case (env points at v1.6.0, binary at v1.6.1) is undefined.
- `os.Executable()` symlink semantics differ Linux (`/proc/self/exe` resolves) vs macOS (may return the invoking symlink path); state whether to `EvalSymlinks`.
- AC3 grep form not pinned; treatment of `commands/init.md`'s existing fallback (grandfather vs migrate) undefined; init chicken-and-egg (is the binary on PATH before init runs?).
- The `commands/<group>/<name>.lib.sh` convention mandates the `$CLAUDE_PLUGIN_ROOT` source form — must be updated in lockstep (paired-update discipline) or the next author reintroduces the bug.
- No version-bump treatment (0029 was 1.6.0→1.6.1; this adds a new subcommand + portability fix); convention requires a sibling test asserting the new version.

Suggestions:
- Rewrite AC4 to assert `zsh -uc "source <lib>"` exits 0 with no stderr (matches the 0029 pattern), OR require each lib to declare a designated `<name>_canary_zsh_source_ok()` no-op the test invokes.
- Pin the zsh-reserved identifier list; proposed set: `status path cdpath fignore mailpath manpath fpath watch psvar signals argv histchars ARGC HISTCHARS`.
- Move OQ1 (persistence) out of scope until a concrete case motivates it.
- Explicitly cover both dogfood and installed-cache layouts in the verify legs.
- Add a version-bump AC or sibling test mirroring 0029.

Positions on open questions: OQ1 (persistence) does **not** block — move to out-of-scope-until-motivated. OQ2 (zsh list) **does** block AC6 — pin it in the spec text.

Convention violations: helper-source convention lockstep; version-bump discipline.

Guardrail violations: none.

## Orchestrator's verified finding

Repo-confirmed, high-confidence: in this repo a root-level `bin/speccraft-state` exists with `commands/`, `templates/`, `.claude-plugin/` as siblings, so "parent of `bin/`" self-derivation *would* resolve correctly if that binary were the one invoked. However, `command -v speccraft-state` on PATH resolves to `/home/vscode/.claude/plugins/cache/dcstolf-tools/speccraft/1.1.0/bin/speccraft-state` — a **stale installed cache copy at version 1.1.0**, not the repo's own binary. Bare `speccraft-state plugin-root` while developing in this repo therefore self-derives to the wrong, old plugin tree. This makes the multi-version/precedence hazard both reviewers raised concrete and present today, not hypothetical, and confirms the precedence rule (env var vs. PATH-binary self-location vs. an explicit dev override) is load-bearing.

## Synthesis

**Quorum note.** Default quorum is 1 approve/approve-with-comments. claude-p's `approve-with-comments` technically satisfies that quorum on its own. However, codex's `changes-requested` is not a minor style objection — it converges with claude-p on nearly every substantive point (precedence/multi-version resolution, AC4's undefined test, OQ2/AC6 verifiability, symlink policy, convention lockstep, version-bump discipline), and the orchestrator's direct repro shows the central precedence hazard is already reproducible in this repo, not a hypothetical edge case. Per the instruction to state this honestly: this review does **not** treat the bare quorum as sufficient to advance. The overall verdict recorded here is `changes-requested`, and the recommended action is to resolve the convergent blocking items in the spec before moving to `/speccraft:spec:plan`.

**Where the two reviewers agree (high-signal, both independently reached the same finding):**
- The zsh-reserved-identifier list (OQ2) must be pinned in the spec text for AC6 to be assertable at all.
- AC4's "first exported function" language is not a valid or reproducible test definition and needs to be rewritten.
- Plugin-root resolution precedence across `CLAUDE_PLUGIN_ROOT`, self-derivation, and (if kept) persistence is unspecified, and the multi-version/stale-copy failure mode is real, not theoretical (confirmed by the orchestrator's repro).
- `os.Executable()` symlink-resolution policy (`EvalSymlinks` or not, Linux vs. macOS) is unstated.
- The sourceable-command-helper convention doc will contradict the new command bodies unless updated in the same change.
- No version-bump AC/sibling-test exists despite this spec shipping a new subcommand plus a portability fix, mirroring 0029's pattern.

**Where they differ (flagged explicitly):**
- Formal verdict: claude-p approve-with-comments vs. codex changes-requested. Resolved above in favor of treating this as changes-requested given the depth of convergence.
- OQ1 framing: codex treats it as "must be resolved before implementation" (i.e., a design decision is owed either way); claude-p says "does not block — move out of scope." These are compatible once you note that *deciding to drop it* (claude-p's proposal) *is* a resolution that satisfies codex's requirement — see Explicit resolutions below.

### Explicit resolutions for the open questions

- **OQ1 (persist plugin root as a fallback?):** Resolve as **out-of-scope-until-motivated**. Self-derivation via `os.Executable()` remains primary; `CLAUDE_PLUGIN_ROOT` remains a corroborating hook-provided source. Do not build a `state.json`-persisted fallback in this spec. If a concrete case later shows self-derivation insufficient (e.g. a binary invoked from a location where the parent-of-`bin/` heuristic fails), open a follow-up spec then. This resolution also discharges codex's "must resolve" concern — the decision *not* to build persistence is itself the resolution.
- **OQ2 (authoritative zsh-reserved list):** Pin the list directly in AC6, not "the documented set." Recommended union of both reviewers' proposals: `status path cdpath fignore mailpath manpath fpath watch psvar signals argv histchars ARGC HISTCHARS`. Cite the source (e.g. the zsh `RESERVED` parameter class in `man zshparam`) so a future author can re-derive/extend it rather than guessing.

## Recommended spec edits

Concrete, actionable changes for the author to fold into a revision:

1. **AC4 — reword the test definition.** Replace "first exported function" language with a reproducible check: `zsh -uc "source <lib>"` exits `0` with no stderr output (mirrors the 0029 sourcing-safety pattern). If functional (not just sourcing-safety) proof is still wanted, additionally require each lib to declare a no-arg canary function, e.g. `<name>_canary_zsh_source_ok()`, that the verify leg invokes and asserts exits 0.

2. **AC6 — pin the identifier list and the grammar it guards.** Inline the resolved OQ2 list (see above) instead of "the documented set." Either broaden the assignment grammar the grep guard checks to cover `local`/`declare`/`typeset`, `read` targets, loop variables, and array/indirect assignments, or explicitly scope AC6 to "top-level plain assignment only" and note the broader grammar as a documented, deliberate limitation.

3. **New/expanded AC — resolution precedence, citing the verified repro.** Add explicit precedence language to AC1/AC2 covering the case where `CLAUDE_PLUGIN_ROOT` (if set), the PATH-resolved `speccraft-state` binary's self-derived root, and (in a dogfood checkout) the repo's own root disagree — e.g. PATH resolves to an older installed-cache copy (as verified: a live 1.1.0 cache copy in this environment) while the working tree is newer. State one of: (a) always prefer self-derivation from the invoked binary's own path, accepting a documented stale-PATH-binary limitation; (b) support an explicit override (e.g. `SPECCRAFT_PLUGIN_ROOT` env var or a dev flag) for the dogfood case; or (c) prefer `CLAUDE_PLUGIN_ROOT` when set and fall back to self-derivation only when absent. Pick one and state its known failure mode explicitly.

4. **AC1/AC2 — symlink policy.** State whether the `os.Executable()` result is passed through `EvalSymlinks` before deriving the parent-of-`bin/` path, and confirm identical behavior is asserted across the Linux and macOS test legs (Linux `/proc/self/exe` already resolves symlinks; macOS may return the invoking symlink path and needs explicit `EvalSymlinks` handling).

5. **AC1 — manifest-identity validation.** Require the resolved directory to also contain `.claude-plugin/plugin.json`, not just `bin/`, `commands/`, `templates/`, so a coincidentally shaped directory cannot be mistaken for the plugin root.

6. **AC3 — pin the grep form and settle `init.md`.** Specify the exact grep pattern used to assert no bare `$CLAUDE_PLUGIN_ROOT` dereferences remain (mirroring 0029's exact-form guard). Explicitly state whether `commands/init.md`'s existing fallback is grandfathered as-is (with a stated reason) or migrated to the same `speccraft-state plugin-root` resolution as every other command doc, and resolve the init-time ordering question: is `speccraft-state` guaranteed to be on PATH before `init.md` runs, or does init need its own bootstrap path?

7. **Convention lockstep.** Update the sourceable-command-helper convention doc in the same change that rewrites command bodies, replacing `source "$CLAUDE_PLUGIN_ROOT/commands/<group>/<name>.lib.sh"` with the new `$PLUGIN_ROOT`-via-`speccraft-state plugin-root` form, so canonical guidance and actual command bodies cannot diverge again.

8. **Version-bump AC.** Add an AC (or sibling test) asserting the version bump for this change, mirroring 0029's 1.6.0→1.6.1 pattern — this spec ships a new subcommand plus a portability fix, the same shape as 0029. If a version bump is genuinely deferred to a release spec, say so explicitly rather than leaving it silent.

9. **AC5 — add a concrete fixture.** Name the exact lib/function under test, the args or fixture `state.json` used, and the expected stdout/stderr/exit code, so "the field-reported failure is gone" is independently checkable instead of restating AC4 in prose.

10. **Dogfood vs. installed-layout coverage (claude-p's top risk).** Add explicit verify-leg coverage for both the repo's self-hosted layout (root `bin/` sibling to `commands/`, `templates/`) and the installed-plugin-cache layout, since the orchestrator's repro shows these two layouts can resolve to different, non-interchangeable roots.

## Action

**Recommend `/speccraft:spec:revise`** to fold in the resolutions above (especially items 1–7, which both reviewers converged on and which the orchestrator's repro confirms is a live, present-day hazard in this repo) before proceeding to `/speccraft:spec:plan`. Advancing on the bare quorum (claude-p's single approve-with-comments) would carry forward an unresolved, concretely-demonstrated multi-version resolution bug and two independently-flagged unverifiable acceptance criteria (AC4, AC6) into planning.
