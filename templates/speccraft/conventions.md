# Conventions

<!-- Copied into your repo by /speccraft:init; it is yours to edit. The Testing
     section's marker is filled by /speccraft:init from your detected stack. -->

## Naming

- Use your language's idiomatic casing for public vs. internal identifiers.
- Name tests so the failing line is self-documenting — encode the subject and the
  scenario (concrete input → expected result).

## Testing

<!-- speccraft:test-command = "" -->

- Your project's test command is recorded in the marker above. `/speccraft:init`
  fills it from the detected stack; edit it to override. Read the effective value
  with `speccraft-state test-command`.
- Prefer table-driven / parameterized tests once there is more than a case or two.
- Keep tests in your stack's conventional location (colocated siblings, a `tests/`
  tree, etc.) — whatever `speccraft-state detect-stack` reports for this repo.

## Errors

- Handle and propagate errors explicitly; never silently discard them.
- Keep error context close to where the failure originates.

## Enforcement

- A rule that must block can carry an `enforce:` HTML comment holding a regex the
  drift scanner checks. Keep any such rule appropriate to THIS repo's stack — do
  not assume a particular language's file layout or test-function shape.
