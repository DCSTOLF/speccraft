# Architecture

## Layering

1. `cmd/` — entrypoints
2. `internal/http/` — HTTP transport, no business logic
3. `internal/domain/` — pure business logic, no I/O
4. `internal/store/` — persistence
5. `internal/httpclient/` — outbound HTTP

Layer N may depend only on layers with higher numbers. (Advisory in v1; enforced via CodeGraphContext if configured.)

## Key decisions

- <decision> — why — link to ADR in history.md

## Boundaries

- Inbound: HTTP only
- Outbound: third-party APIs via `internal/httpclient`
