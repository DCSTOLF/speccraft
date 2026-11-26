# `gitignore.pre0054` — provenance

AC14a requires the installed-base claim to be proven against a **checked-in**
`.gitignore` representing a repo initialized *before* spec 0054 — "not a shape
the test constructs at run time, which would prove the installed-base claim
against a shape the test itself chose".

## What this file is

`.speccraft/state.json` plus a trailing newline. That is exactly, and only,
what `/speccraft:init` writes into a host repo's `.gitignore`:

> 7. Append `.speccraft/state.json` to `<repo>/.gitignore` (creating if absent).
>    Only append if the line isn't already present.
>
> — `commands/init.md` step 7

Verified byte-identical at `origin/main` and in the working tree at the time
this fixture was created (spec 0054 does not touch that step), so this is the
pre-0054 shape rather than a reconstruction of it.

## A correction to AC14a's wording

AC14a describes the fixture as "byte-identical to the template as it shipped
*before* this spec". There is no template `.gitignore` to copy: `templates/`
ships no such file, and the host repo's `.gitignore` is produced by init's
append step above. The fixture is therefore pinned to that step's documented
output, which is the same claim the AC is reaching for — what an
already-initialized repo actually has on disk.

A real host repo would carry its own project lines too. They are deliberately
absent: the only property under test is that **nothing here mentions
`.review-rounds`**, so the round directory can only be ignored by the
`.gitignore` that `review_round_dir_create` writes *inside*
`.speccraft/.review-rounds/`. That is what makes AC14a's "ignored with no
migration" true — no re-init, no template update, no edit to the host's file.

Adding unrelated project lines would make the fixture less decidable, not more
realistic: a stray pattern that happened to cover the round dir would mask the
very mechanism being proven.
