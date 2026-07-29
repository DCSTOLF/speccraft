# Open questions — speccraft v1

Ambiguities found during implementation, with call and rationale.

---

## OQ-1: plugin.json install flow

**Ambiguity:** Phase 0 done-criteria says "plugin shows as Enabled" via `/plugin marketplace add <local-path>`.
The exact Claude Code plugin install workflow from a local path was not tested at kickoff time.

**Call:** Implement the plugin.json per spec (§8.2). If the local-path install flow differs from
`/plugin marketplace add`, note it here. The done-criteria for T0.4 may require user to verify
since it requires an interactive Claude Code session.

**Status:** Open — to verify during Phase 0.

---

## OQ-2: devcontainer files already seeded

**Ambiguity:** Phase 0.5 requires building `.devcontainer/` files, but they already exist in the
repo seed. Should they be treated as done, or verified/updated?

**Call:** Verify existing files match spec requirements (§18.1). Update where needed. Mark T0.5.1–T0.5.4
as done if files match spec. Tests/e2e run.sh also already exists — verify it exits 0.

**Status:** Open — to verify during Phase 0.5.

---

## OQ-4: Stale `.speccraft/graph` reference in e2e test (FIXED)

**Bug found:** `tests/e2e/run.sh` line 105 checked for `.speccraft/graph` in `.gitignore`.
`.speccraft/graph/` is the removed code-graph feature (§13 of spec, KICKOFF §7).

**Fix applied:** Removed the stale assertion. The remaining check for `.speccraft/state.json` is correct.

**Stale Dockerfile comment** about "CGO + tree-sitter" also updated.

**Status:** Resolved — stale references removed.

---

## OQ-3: Stop hook not in Phase 0 task list

**Ambiguity:** `hooks/stop.sh` is mentioned in the Phase 8 build list but `hooks.json` in §12.1
includes a Stop hook entry. Phase 1 adds hooks.json but only with SessionStart.

**Call:** Add Stop hook to hooks.json in Phase 8 as specified. In Phase 1 only add SessionStart;
add others progressively as each phase builds the corresponding script.

**Status:** Resolved — proceed as stated.
