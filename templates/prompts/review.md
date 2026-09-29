You are reviewing a software specification. Be rigorous but constructive.

Output in this exact structure:

```yaml
verdict: <approve | approve-with-comments | changes-requested | reject>
concerns:
  - "<concern 1>"
  - "<concern 2>"
suggestions:
  - "<suggestion 1>"
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

Then a free-form discussion section after the YAML.

Specification follows below. Repo memory is included in two tiers.

**Inline files** are pasted in full — read them where they are.

**Reference files** are given as a path, a byte size and a heading index, and
their bodies are deliberately NOT pasted. Open each one with your own tools,
read the sections the heading index tells you are relevant, and then:

- return an entry in `reference_access` for **every** reference path you were
  given, with the SHA-256 of the file's bytes as you read them;
- report any you could not read in `reference_access_failures`.

The expected digests are withheld from this prompt on purpose: a digest cannot
be produced without reading the bytes, which is the point. A verdict whose
`reference_access` is absent, incomplete, or carries a digest that does not
match **does not count** toward the review — it is treated exactly like a
timeout. If you cannot open these paths at all, say so in
`reference_access_failures` rather than reviewing a file you never read.
