---
description: "One-time bypass of the TDD invariant. Reason is logged."
argument-hint: "<reason>"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Grant a one-time bypass of the TDD invariant for "$1".

Steps:

1. Confirm there is an active spec (`speccraft-state get active_spec`).
   If none, warn: "No active spec. The TDD invariant is already relaxed
   for non-production paths. Are you sure you need an override?"

2. Log the bypass in the active spec's `tasks.md` under a `## Bypasses`
   section:
   ```
   ## Bypasses
   - <ISO date> — override: <reason>
   ```

3. Set the session flag that allows the next single production-file edit
   without the sibling-test check:
   ```bash
   speccraft-state set override_pending true
   ```
   `speccraft-guard` checks this flag via `ConsumeOverride` and clears it
   atomically on the first guarded production-file edit.

4. Confirm to the user: "Override granted. The next production file edit
   will bypass the TDD invariant. Reason logged in tasks.md."
