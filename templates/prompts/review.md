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
```

Then a free-form discussion section after the YAML.

Specification follows below. Repo memory (guardrails, conventions, architecture)
is included as additional context.
