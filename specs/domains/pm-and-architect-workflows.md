# Domain: pm-and-architect-workflows

Optional PM/Architect upstream stages: `pm:*`/`arch:*` command namespaces, `product/`+`design/` artifact trees, their agents, independent state lanes, and pull-only spec linkage.

- Two optional upstream command namespaces parallel `spec:*` — `/speccraft:pm:{new,review,prioritize,close}` and `/speccraft:arch:{new,review,decide,close}` — with artifacts under `product/NNNN-slug/` (`brief.md`, `review.md`, optional `roadmap.md`) and `design/NNNN-slug/` (`design.md`, `review.md`, ADRs); ids are allocated independently per tree as highest-NNNN+1 and never reused (spec 0022)
- Specs stay a fully standalone workflow: with no `product/`/`design/` present every `spec:*` command and the TDD hooks behave byte-for-byte as before, and the three stages are advisory, never a gate (spec 0022)
- Four new agents — `pm-author`/`arch-author` (mirroring `spec-author`) and `pm-critic`/`arch-critic` (mirroring `spec-critic`) — back the new stages, with `cross-reviewer` backing `pm:review`/`arch:review` unchanged and `arch:close` routing through `memory-keeper` to update `.speccraft/architecture.md` and append ADRs (no new store) (spec 0022)
- The three active lanes are independent: `pm:close` clears `active_product`, `arch:close` clears `active_design`, `spec:close` clears `active_spec`, and a close NEVER touches another lane (spec 0022)
- Stage linkage is pull-only: a spec may carry an optional advisory `informed-by: [product/NNNN, design/NNNN]` frontmatter and `spec:new --from product/<id>` (accepting even a `closed` brief) pre-populates Why/What and sets `informed-by`, but a missing/deleted/closed referent never blocks any `spec:*` command (non-fatal note) (spec 0022)
