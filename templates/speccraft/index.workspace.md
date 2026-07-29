<!-- speccraft:kind = workspace -->
# <workspace name>

<one-sentence description of what this workspace coordinates>

This repository is a speccraft **workspace root**: a coordination layer over
several member repositories, not a code repository itself. Cross-repo work is
planned as a *design* and driven across members by the architect conductor.

## Members

The authoritative member list lives in `workspace.yml` at this root (surfaced by
`speccraft-state list-members`). Each member is an independently-initialized
speccraft `repo` with its own `.speccraft/` and `specs/`.

- <member-path> — <one-line role>
- <member-path> — <one-line role>

## Hard rules (see guardrails.md)

- <workspace-level rule 1>
- <workspace-level rule 2>
- <workspace-level rule 3>

## Where to look

- Member manifest: `workspace.yml`
- Cross-repo designs: `design/<id>/`
- Orchestration ledger: `.speccraft/ledger.md` (created on first orchestration)
- Conductor runbook: `/speccraft:arch:orchestrate`

## Active design

none

## Recent decisions (last 3)

_none yet — updated by /speccraft:arch:close_
