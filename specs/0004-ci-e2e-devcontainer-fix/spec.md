---
id: "0004"
title: "Fix CI e2e devcontainer exec failure"
status: closed
created: 2026-05-15
authors: [daniel]
packages: [".github/workflows/ci.yml"]
related-specs: []
---

# Spec 0004 — Fix CI e2e devcontainer exec failure

## 1. Summary

The `e2e-devcontainer` job in CI fails with "Dev container not found." because
`devcontainer exec` requires a running container but the workflow only calls
`devcontainer build`, which produces an image without starting a container.
Insert a `devcontainer up` step so a container instance exists before `exec`
tries to attach.

## 2. Why

`devcontainer build` compiles the Docker image and exits. It leaves no running
container behind. `devcontainer exec` then fails immediately because there is
nothing to exec into. The fix is one missing lifecycle step: `devcontainer up`,
which creates and starts the container (building the image if necessary).

## 3. What

Add a `devcontainer up --workspace-folder .` step between `build` and `exec`
in `.github/workflows/ci.yml`. Optionally collapse the standalone `build` step
into `up` since `up` already performs a build.

### Before

```yaml
- name: Build devcontainer
  run: devcontainer build --workspace-folder .
- name: Run e2e tests
  run: |
    devcontainer exec --workspace-folder . bash tests/e2e/run.sh
```

### After (minimal fix — keep build for cache clarity, add up)

```yaml
- name: Build devcontainer
  run: devcontainer build --workspace-folder .
- name: Start devcontainer
  run: devcontainer up --workspace-folder .
- name: Run e2e tests
  run: |
    devcontainer exec --workspace-folder . bash tests/e2e/run.sh
```

### After (collapsed — simpler)

```yaml
- name: Start devcontainer
  run: devcontainer up --workspace-folder .
- name: Run e2e tests
  run: |
    devcontainer exec --workspace-folder . bash tests/e2e/run.sh
```

## 4. Acceptance criteria

1. The `e2e-devcontainer` job completes without "Dev container not found."
2. `devcontainer exec` reaches `tests/e2e/run.sh` (the script may still fail for
   unrelated reasons; that is out of scope here).
3. No other CI jobs are affected.

## 5. Out of scope

- Fixing any failures inside `tests/e2e/run.sh` itself.
- Caching the devcontainer image between runs.
- Running e2e on pull requests (currently gated to `push` to `main`).
