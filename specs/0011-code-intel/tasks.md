---
spec: "0011"
---

# Tasks

- [x] T1 — Add `specs/0011-code-intel/verify.sh` codifying AC1/AC2/AC3 as grep assertions (RED — fails on current main)
- [x] T2 — Edit `skills/speccraft-context/SKILL.md` lines 24-36: replace CodeGraphContext routing block with neutral deferral wording, retain "structural queries are a real need" acknowledgment, ensure `defer` token present (GREEN A — satisfies AC1)
- [x] T3 — Edit `commands/init.md` lines 111-113: reframe CodeGraphContext as one example ("such as CodeGraphContext") of a code-intel MCP server; preserve `call-graph`/`symbol-search` trigger so the conditional install-suggestion still fires (GREEN B — satisfies AC2)
- [x] T4 — Edit `templates/speccraft/architecture.md` line 11: drop "; enforced via CodeGraphContext if configured" so the parenthetical reads `(Advisory in v1.)` (GREEN C — satisfies AC3)
- [x] T5 — Re-run `bash specs/0011-code-intel/verify.sh`; confirm exit 0 and final cross-reference scan for awkward wording in the three edited sections (REFACTOR — optional cleanup, no README changes per §Out of scope)
