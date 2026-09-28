# FORBIDDEN FIXTURE — spec 0052 AC27/AC29

All four markers are present, but the budget check runs AFTER dispatch. That is
the ordering that makes the whole spec pointless: the payload has already been
handed to the CLI by the time anything measures it, so an over-budget round
still times out at 600 s and the refusal arrives too late to prevent anything.

```bash
source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
review_compose_payload "$TEMPLATE" "$ROUND_SPEC" --inline ... > "$ART"
review_dispatch_payload "$AGENT_CMD" "$INPUT_MODE" "$ART"
review_budget_check "$BYTES" "$INPUT_MODE"
```
