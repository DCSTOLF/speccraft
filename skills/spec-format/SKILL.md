---
name: spec-format
description: "Canonical spec.md/plan.md templates, frontmatter rules, status state machine, and examples. Used by spec-author and tdd-planner to produce correctly formatted output."
---

# spec-format

This skill provides the canonical format for speccraft documents.

## spec.md frontmatter

```yaml
---
id: "<NNNN>"          # 4-digit zero-padded, allocated by /spec:new
title: "<title>"       # Human-readable title
status: draft          # draft | reviewed | planned | in-progress | closed | archived
created: YYYY-MM-DD
authors: [claude]
packages: ["pkg/path"] # Go package paths this spec touches
related-specs: []      # IDs of related specs
domains: [area]        # optional; routes /spec:close consolidation to
                       # specs/domains/<area>.md. Authoritative when present —
                       # otherwise the area is seeded from the title and
                       # presented for confirmation.
started_at_sha: ""     # set when status moves to in-progress (for /spec:close diff)
---
```

## Status state machine

```
draft → reviewed → planned → in-progress → closed
                                         ↘ archived
```

- `draft` → `reviewed`: after `/spec:review` achieves quorum
- `reviewed` → `planned`: after `/spec:plan` writes plan.md and tasks.md
- `planned` → `in-progress`: when `/spec:implement` begins
- `in-progress` → `closed`: after `/spec:close` completes
- `in-progress` → `blocked`: when parked by `/spec:new` for a new spec
- any → `archived`: manual; means "abandoned but kept for reference"

## plan.md frontmatter

```yaml
---
spec: "<NNNN>"
status: planned        # planned | in-progress | closed
strategy: tdd
---
```

## tasks.md frontmatter

```yaml
---
spec: "<NNNN>"
contract: done-means-v1   # opt-in; see below
---
```

### Task line format

Base form: `- [x] TN — <description>` or `- [ ] TN — <description>`.

Under `contract: done-means-v1` (spec 0047), a task also carries sub-checkboxes
and a `done:` line:

```markdown
---
spec: "0047"
contract: done-means-v1
---

# Tasks

- [x] T1 — single deliverable
  done: $ go test ./pkg/ -run Test_Thing
- [ ] T2 — several deliverables, so decompose
  - [x] T2.a — parser
  - [x] T2.b — checks
  - [ ] T2.c — wiring
  done: $ grep -q 'case "thing":' cmd/main.go
- [ ] T3 — not started yet
  done: prose is allowed, but it is never verified
```

Grammar:

- A **task** is a checkbox at column 0. Its id may be dotted (`T0.1`, `T0.5.1`) —
  only indentation makes a sub-checkbox.
- A **sub-checkbox** is an indented checkbox whose id is its parent's id plus one
  more `[A-Za-z0-9]+` segment. One level deep. An indented bullet that does not
  match this is prose and is ignored, at any depth.
- A **`done:` line** is indented exactly 2 spaces and belongs to the nearest
  preceding task. Exactly one per task, non-empty, required for every task under
  the contract regardless of tick state.
- A `done:` value starting with `$` is an **executable predicate**, run by
  `speccraft-state tasks-verify --run` under `/bin/sh -c` from the repo root.
  Any other value is prose: articulation only, never verified. A bare `$` with no
  command is malformed, not prose — it would otherwise look executable and be
  silently waived.

Note the example above: `T2` stays `[ ]` precisely because `T2.c` is unfinished.
Ticking it would be the parent/child violation the gate exists to catch.

`speccraft-state tasks-verify <tasks.md> [--run]` exits `0` clean, `1` violations,
`2` malformed. `/speccraft:spec:close` runs it as its completion gate. The
parent/child check (a `[x]` parent with a `[ ]` sub-checkbox) applies to **all**
tasks.md files, contract key or not; the `done:` requirement applies only under
the contract.

## review.md frontmatter

```yaml
---
spec: "<NNNN>"
reviewers: [agent1, agent2]
quorum: 1
verdict: approve | approve-with-comments | changes-requested | reject
generated: ISO-8601-timestamp
---
```

## changelog.md frontmatter

```yaml
---
spec: "<NNNN>"
closed: YYYY-MM-DD
---
```

## Slug format

Slugs are kebab-case: lowercase, `a-z0-9-` only, derived from the spec title.
Examples: `add-health-endpoint`, `rate-limit-public-api`, `speccraft-v1`

## Examples

See `specs/0001-speccraft-v1/` for a live example of this project's spec.
