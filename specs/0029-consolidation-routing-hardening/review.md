---
spec: "0029"
reviewed: 2026-06-26
verdict: approve-with-comments
quorum_met: true
agents: [codex, claude-p]
---

# Cross-model review — 0029

## codex (gpt-5.5)

**Verdict:** changes-requested

Concerns:
- Fix B is not testable as written: "prefer a good existing-domain match" is a model judgment, but no deterministic matching rule, prompt contract, or observable proposal format is specified.
- The zsh acceptance criterion may overpromise. A shebang does not matter when sourced by zsh, so the spec must verify the whole sourced file is zsh-parseable, not only that BASH_SOURCE has a fallback.
- AC3 appears to conflict with Fix B unless clarified: it says the absent-domains title-slug seed is unchanged, while Fix B says routing uses the existing-domain list to prefer an existing area.
- The grep regression guard is useful but underspecified: "or equivalent fallback" is hard to enforce with a simple oracle and may miss syntactic variants or flag acceptable code.

Suggestions:
- Define `consolidate_existing_domains` output ordering, likely sorted bytewise, so prompts and tests are stable.
- Separate deterministic seed behavior from model proposal behavior: keep `consolidate_routing_seed` unchanged, add a domain-list helper, and document exactly how `memory-keeper` receives both.
- Add a minimal zsh smoke test that actually runs `zsh -c 'set -u; source ...; typeset -f consolidate_existing_domains >/dev/null'`, skipping cleanly if zsh is unavailable.
- Make the structural e2e fixture concrete: one existing domain, one unrelated title, one matching title, and explicit assertions that `.speccraft/*.md` are unchanged.

## claude-p (claude-opus-4-8)

**Verdict:** approve-with-comments

Concerns:
- AC1(a) testability: the proposed "simulated-unset harness" in bash does NOT faithfully reproduce the zsh failure. `set -u; unset BASH_SOURCE; source file` re-populates BASH_SOURCE[0] to the sourced file path inside the source — bash auto-manages it, so a bash-only harness passes even against the BROKEN code. A faithful red-pinning test must invoke real zsh (`zsh -uc 'source .../consolidate.lib.sh'`). The spec lists zsh OR a simulated harness as equivalent; they are not.
- Dependency unstated: AC1(a)'s faithful test requires zsh in the test/CI bats environment. zsh 5.8.1 is present in this devcontainer, but the spec never states zsh as a test prerequisite nor confirms the CI bats runner has it. If CI lacks zsh and the test silently falls back to the unfaithful bash harness, the regression pin is hollow.
- AC1(b) guard predicate vs. "or equivalent" fuzziness: the regression guard is a mechanical grep, but What/Decisions repeatedly permit `${BASH_SOURCE[0]:-$0} (or an equivalent)`. A pure grep cannot validate semantic equivalence of an arbitrary alternative idiom — it will either false-positive on a valid alternative or be loosened until it stops catching the real bug.

Suggestions:
- Mandate the canonical `${BASH_SOURCE[0]:-$0}` form (single idiom) so AC1(b)'s grep is exact; drop "or equivalent", or enumerate the precise accepted alternatives the guard recognizes.
- Add a one-line in-code comment at the fix site explaining WHY the fallback is correct cross-shell (bash always populates BASH_SOURCE so the fallback never fires there; zsh sets $0 to the sourced file by default, so $0 is the right value precisely where the fallback fires).
- Given the documented 0025->0027->0028 fixture-flakiness lineage, apply that lineage's own convention to AC6: reconstruct AC6's "matches existing domain" vs "no match" corpus at the credit-free bats layer (asserting `consolidate_existing_domains` returns the expected set that feeds the proposal).
- State explicitly that Fix C is mitigation, not enforcement: a grep oracle pins the presence of disambiguating wording but cannot prevent an agent from writing requirements into `.speccraft/`. No deterministic guard exists for this.

## Synthesis

Both reviewers examined the same three factual anchors that make 0029 well-scoped: exactly 8 `*.lib.sh` files exist under `commands/`, only `consolidate.lib.sh` uses the `BASH_SOURCE` dir-resolution idiom (it is the sole lib that sources a sibling), and the merge/locator/archive/dir-move engine from 0025 is explicitly out of scope. The two reviewers agreed on the substance of every material concern; the only difference in verdict reflects appetite, not disagreement on facts. Quorum is met.

The carry-forward findings below are deduplicated, merged from both reviewers, and ranked by severity. They must be folded into spec.md before implementation begins.

## Carry-forward findings (fold into spec)

**CF-1 (MUST) — AC1(a) bash-harness is unfaithful; pin with real zsh.**
`set -u; unset BASH_SOURCE; source file` inside bash re-populates `BASH_SOURCE[0]` automatically — bash's internal bookkeeping fires before the lib body runs. A bash-only harness therefore passes even against the broken code. The spec's "zsh, or a simulated-unset harness" treats the two as equivalent; they are not. Fix: AC1(a) must mandate `zsh -uc 'source .../consolidate.lib.sh'` as the primary test. The bash-harness alternative must be dropped. Declare zsh a test prerequisite and add a skip-if-absent guard (`command -v zsh || skip "zsh required"`). Confirm the CI bats runner has zsh — it is present as zsh 5.8.1 in the devcontainer, which is the same environment. The real-zsh source test also subsumes codex's concern that the whole sourced file must be zsh-parseable: invoking `zsh -uc 'source ...'` exercises the entire file, not only the `BASH_SOURCE` expansion line.

**CF-2 (MUST) — Pin the exact idiom; drop "or equivalent" from AC1(b) and Decisions.**
The regression guard is a grep oracle. A grep cannot validate semantic equivalence of an arbitrary "equivalent" idiom — it will either false-positive on a valid alternative or be loosened until it stops catching the real bug. Fix: replace every occurrence of `${BASH_SOURCE[0]:-$0} (or an equivalent)` with the single canonical form `${BASH_SOURCE[0]:-$0}`. AC1(b)'s grep predicate then has an exact target and cannot be gamed by a syntactically different but semantically equivalent form.

**CF-3 (MUST) — Resolve the Fix B / AC3 apparent conflict; pin AC6 at bats layer.**
AC3 says the title-slug seed is unchanged (regression pin for 0025 AC2). Fix B says routing uses the existing-domain list to prefer an existing area. As written, these could be read as contradicting each other. Fix: make the separation explicit in the spec. `consolidate_routing_seed` remains byte-unchanged (deterministic; AC3 pins 0025 AC2). `consolidate_existing_domains` is a SEPARATE deterministic input that enumerates live domains in stable sorted order (define: sorted bytewise, one name per line) and is fed alongside the seed to the `memory-keeper` model step. The "prefer existing match else propose new" decision is model-tier and confirm-gated, as Fix B already states. Additionally, apply the 0025->0027->0028 fixture-flakiness lineage's own convention to AC6: pin `consolidate_existing_domains`'s output at the bats layer (given a known fixture corpus, the helper returns the expected sorted set). This credit-free bats assertion fails on every bats run if the corpus helper regresses, not only during the credit-gated e2e.

**CF-4 — State explicitly that Fix C is mitigation, not enforcement.**
The verify.sh grep oracle pins the presence of disambiguating wording in `close.md` and `memory-keeper.md`. It cannot prevent an agent from writing requirements into `.speccraft/` — a hook cannot distinguish a consolidation write from a legitimate `Mode: close` write to the same file. Add a residual-risk note to the spec (one sentence in Decisions or a note below Fix C) so implementers and future reviewers know the boundary of the guarantee.

**CF-5 (nice-to-have) — Add an in-code comment at the fix site.**
Add a comment at the `${BASH_SOURCE[0]:-$0}` fix site explaining why the idiom is correct cross-shell: bash always populates `BASH_SOURCE` so the `:-$0` fallback never fires there; zsh sets `$0` to the sourced file when sourcing, so `$0` is exactly right where the fallback fires. This prevents a future "simplify" commit from regressing back to the broken form.

**CF-6 (nice-to-have) — Make the AC6 e2e fixture concrete.**
Specify the fixture: one pre-existing domain, one spec whose title matches that domain (→ routed into existing file), one spec whose title does not match any domain (→ new domain proposed and created on confirm). Add explicit assertions that `.speccraft/*.md` files are byte-unchanged after both consolidation runs.

## Per-agent verdicts

```yaml
# codex (gpt-5.5)
verdict: changes-requested
concerns:
  - "Fix B is not testable as written: 'prefer a good existing-domain match' is a model judgment, but no deterministic matching rule, prompt contract, or observable proposal format is specified."
  - "The zsh acceptance criterion may overpromise. A shebang does not matter when sourced by zsh, so the spec must verify the whole sourced file is zsh-parseable, not only that BASH_SOURCE has a fallback."
  - "AC3 appears to conflict with Fix B unless clarified: it says the absent-domains title-slug seed is unchanged, while Fix B says routing uses the existing-domain list to prefer an existing area."
  - "The grep regression guard is useful but underspecified: 'or equivalent fallback' is hard to enforce with a simple oracle and may miss syntactic variants or flag acceptable code."
suggestions:
  - "Define `consolidate_existing_domains` output ordering, likely sorted bytewise, so prompts and tests are stable."
  - "Separate deterministic seed behavior from model proposal behavior: keep `consolidate_routing_seed` unchanged, add a domain-list helper, and document exactly how `memory-keeper` receives both."
  - "Add a minimal zsh smoke test that actually runs `zsh -c 'set -u; source ...; typeset -f consolidate_existing_domains >/dev/null'`, skipping clearly if zsh is unavailable."
  - "Make the structural e2e fixture concrete: one existing domain, one unrelated title, one matching title, and explicit assertions that `.speccraft/*.md` are unchanged."
guardrail_violations: []
convention_violations: []
```

```yaml
# claude-p (claude-opus-4-8)
verdict: approve-with-comments
concerns:
  - "AC1(a) testability: the proposed 'simulated-unset harness' in bash does NOT faithfully reproduce the zsh failure. I verified that `set -u; unset BASH_SOURCE; source file` re-populates BASH_SOURCE[0] to the sourced file path *inside* the source — bash auto-manages it, so a bash-only harness passes even against the BROKEN code. A faithful red-pinning test must invoke real zsh (`zsh -uc 'source .../consolidate.lib.sh'`). The spec lists zsh OR a simulated harness as equivalent; they are not."
  - "Dependency unstated: AC1(a)'s faithful test requires zsh in the test/CI bats environment. zsh 5.8.1 is present in this devcontainer, but the spec never states zsh as a test prerequisite nor confirms the CI bats runner has it. If CI lacks zsh and the test silently falls back to the unfaithful bash harness, the regression pin is hollow."
  - "AC1(b) guard predicate vs. 'or equivalent' fuzziness: the regression guard is a mechanical grep ('references BASH_SOURCE[0] without :-$0 fallback'), but What/Decisions repeatedly permit '${BASH_SOURCE[0]:-$0} (or an equivalent)'. A pure grep cannot validate semantic equivalence of an arbitrary alternative idiom — it will either false-positive on a valid alternative or be loosened until it stops catching the real bug. Pin the exact accepted form(s)."
suggestions:
  - "Mandate the canonical `${BASH_SOURCE[0]:-$0}` form (single idiom) so AC1(b)'s grep is exact; drop 'or equivalent', or enumerate the precise accepted alternatives the guard recognizes."
  - "Add a one-line in-code comment at the fix site explaining WHY the fallback is correct cross-shell (bash always populates BASH_SOURCE so the fallback never fires there; zsh sets $0 to the sourced file by default, so $0 is the right value precisely where the fallback fires)."
  - "Given the documented 0025->0027->0028 fixture-flakiness lineage, apply that lineage's own convention to AC6: reconstruct AC6's 'matches existing domain' vs 'no match' corpus at the credit-free bats layer (asserting `consolidate_existing_domains` returns the expected set that feeds the proposal)."
  - "State explicitly that Fix C is mitigation, not enforcement: a grep oracle pins the *presence* of disambiguating wording but cannot prevent an agent from writing requirements into `.speccraft/`. No deterministic guard exists for this."
guardrail_violations: []
convention_violations: []
```

## Recommended next action

Fold CF-1 through CF-6 into `spec.md`:

1. CF-1: Replace AC1(a)'s "zsh, or a simulated-unset harness" with a mandatory `zsh -uc 'source ...'` test; declare zsh a prerequisite; add `command -v zsh || skip` guard; drop the bash-harness equivalence.
2. CF-2: Replace all instances of `${BASH_SOURCE[0]:-$0} (or an equivalent)` with the single canonical form `${BASH_SOURCE[0]:-$0}` throughout What, Decisions, and AC1(b).
3. CF-3: Explicitly separate `consolidate_routing_seed` (unchanged, deterministic) from `consolidate_existing_domains` (new, sorted bytewise); clarify that "prefer existing match" is model-tier; add a bats-layer AC for `consolidate_existing_domains` output against a known fixture.
4. CF-4: Add a one-sentence residual-risk note under Fix C that it is mitigation, not enforcement.
5. CF-5: Note that the fix site should carry an in-code comment explaining the cross-shell correctness argument.
6. CF-6: Expand the AC6 fixture description to the concrete three-case scenario with `.speccraft/*.md` byte-unchanged assertions.

Once CF-1 through CF-4 are incorporated (the MUSTs), run `/speccraft:spec:plan` to generate the implementation task list.
