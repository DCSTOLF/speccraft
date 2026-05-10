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
---
```

Task line format: `- [x] TN — <description>` or `- [ ] TN — <description>`

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
