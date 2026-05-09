# Conventions

## Naming

- Exported types and functions: PascalCase
- Unexported: camelCase
- Test functions: `Test_<Subject>_<Scenario>` <!-- enforce: regex pattern="^func Test[A-Z]" scope="**/*_test.go" -->

## Errors

- Wrap with `fmt.Errorf("...: %w", err)`, never bare returns of foreign errors.
- Sentinel errors live alongside the package that returns them.

## Tests

- Table-driven tests are preferred for >2 cases.
- Every exported function in `internal/domain/` should have at least one test. (Advisory in v1.)

## Logging

- Use `slog` only. No `fmt.Println` outside `cmd/`. <!-- enforce: regex pattern="fmt\\.Print(ln|f)?" scope="!cmd/" -->
