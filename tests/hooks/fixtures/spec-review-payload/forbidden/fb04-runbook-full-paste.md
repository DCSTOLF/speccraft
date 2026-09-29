# FORBIDDEN FIXTURE — spec 0052 AC27/AC29

The pre-0052 `commands/spec/review.md` step 3, verbatim. This is the bite proof
for `runbook_no_full_paste`: the checker is run against the real runbook (must
pass) and against this file (must reject). A bare `! grep -q 'conventions.md'`
against the runbook alone would be inert — it would also pass on a runbook that
never mentioned the reference files at all, which is a different bug.

3. For each selected agent, invoke the `aux-delegator` subagent with payload:
   - The spec.md content
   - The relevant slice of `.speccraft/` (index.md + guardrails.md +
     architecture.md + conventions.md)
   - The review prompt template from
     `$PLUGIN_ROOT/templates/prompts/review.md`

Those two lines are the whole bug: `conventions.md` is 121 KB in this repo and
`architecture.md` 38 KB, and both were pasted in full into every reviewer's
prompt with nothing bounding the total.
