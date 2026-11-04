RE-REVIEW BRIEF — assess ONLY the deltas since last review + regressions

This spec was already reviewed in a prior round. Do NOT re-litigate sections that
did not change. Focus your judgment on two things:

1. The deltas since the last review — the sections listed below changed and are
   the subject of this round:

{{CHANGED_SECTIONS}}

   Section-level diff:

{{DIFF}}

2. Regressions — sweep the previously-approved acceptance criteria (the sections
   NOT listed above) and confirm the changes above did not break or contradict
   them. The full current spec and the prior review are attached below as
   context so you can check for regressions, but assess only the deltas and their
   ripple effects; settled, unchanged sections stay settled unless a delta breaks
   them.

Output the same structured verdict block as a normal review, scoped to the
deltas and any regressions you find. Use exactly this shape — the
`reference_access` entries are parsed, so `- path:` and `sha256:` must each be
on their own line, as below. A map (`<path>: <digest>`) or both keys on one
line does not parse, and a verdict whose attestation does not parse counts
toward **neither** predicate, exactly like a timeout:

```yaml
verdict: "<approve|approve-with-comments|changes-requested|reject>"
concerns:
  - "<concern, scoped to a delta or a regression it causes>"
suggestions:
  - "<suggestion>"
guardrail_violations:
  - rule: "<which rule>"
    location: "<which paragraph>"
convention_violations:
  - rule: "<which rule>"
    location: "<which paragraph>"
reference_access:
  - path: "<repo-relative path, exactly as given to you>"
    sha256: "<the digest you computed AFTER reading that file>"
reference_access_failures:
  - path: "<path>"
    reason: "<why you could not read it>"
```

Return an entry in `reference_access` for **every** reference path you were
given, with the SHA-256 of the file's bytes as you read them, and report any you
could not read in `reference_access_failures`. Use `[]` for either list when it
is empty. The expected digests are withheld from this prompt on purpose: a
digest cannot be produced without reading the bytes, which is the point.

Then a free-form discussion section after the YAML.
