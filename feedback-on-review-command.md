
`/speccraft:spec:review` sends the whole of .speccraft/ to every reviewer, and nothing limits the size of the memory files, so reviews fail once a project has been running for a while

What happened (tessera-cdc, 2026-09-25)
- Step 3 of commands/spec/review.md pastes spec.md, index.md, guardrails.md, architecture.md and conventions.md in full into each reviewer's prompt.
- After about 100 specs, that prompt was 622 KB per reviewer. Of that, conventions.md was 339 KB and architecture.md 227 KB. On 2026-08-15 they had been 100 KB and 33 KB.
- The claude-p reviewer is set to input = "argv", so the whole prompt went in as one command-line argument. Its working limit has been about 70 KB within the 600 s timeout. Reviews timed out or failed, and I had to tell reviewers by hand to "pass paths, don't paste files."
- codex gets the prompt on stdin, so it avoids the argument limit but still reads all 622 KB.

Why the files grow without limit
- At every close, memory-keeper adds to conventions.md and architecture.md. Nothing ever shrinks them.
- history.md has a size check that suggests compacting and a /speccraft:history:compact command. These two files have neither.
- Their entries turn into retrospectives: some lines in architecture.md were 14 KB, and its "one line per spec" Change log reached 89 KB.

Workaround I used: condensed both files by hand (to 44 KB and 21 KB), with the originals archived word for word. The review prompt dropped to 121 KB, which is still above the claude-p limit, because the spec plus guardrails alone are about 50 KB.

Suggested changes
1. Review prompt: pass file paths and let the reviewer read them with its own tools, or send only the sections the spec touches, not whole files. At minimum:
   - put a size limit on the prompt, and warn or refuse clearly when it's exceeded instead of timing out;
   - default the claude-p reviewer to input = "stdin".
2. Size limits on memory files: add conventions.md and architecture.md to the check that already runs at close for history.md. Warn above a threshold (e.g. 50 KB and 30 KB) and point to a compaction command.
3. Compaction command for these files: something like /speccraft:memory:compact, following the history compaction pattern:
   - condense each entry to its rule (claim, why it matters, which spec);
   - move the originals word for word to .speccraft/memory-archive/;
   - require confirmation before rewriting;
   - leave headings unchanged, since the project's code comments cite them by name.
4. Prevent it at close: give memory-keeper a per-entry limit in close mode: one bullet in conventions, one line of about 160 characters or less in the architecture change log. Anything longer should go to history.md.

Close-time updates put the wrong content in these files, not just too much of it

These files are supposed to hold one kind of content each, with no overlap:

┌────────────────────┬───────────────────────────────────────────┐
│        File        │                Should hold                │
├────────────────────┼───────────────────────────────────────────┤
│ history.md         │ why it was done (reasoning and write-ups) │
├────────────────────┼───────────────────────────────────────────┤
│ specs/domains/*.md │ what the system must do (requirements)    │
├────────────────────┼───────────────────────────────────────────┤
│ conventions.md     │ how to work here (craft and traps)        │
├────────────────────┼───────────────────────────────────────────┤
│ architecture.md    │ where code lives today                    │
└────────────────────┴───────────────────────────────────────────┘

memory-keeper's close mode does not respect that split:

- architecture.md became a second history. Its Change log, meant as "one line per spec", reached 89 KB, with 47 of its 118 lines over 1 KB. Those lines retold each spec's reasoning, which history.md already holds. Spec 0102's close even added a whole ### … (spec 0102) section to the Change log.
- Requirements were copied into both files. That 0102 section restates requirements already written into specs/domains/engine-mysql.md at consolidation, and conventions.md got a matching section. Once the same rule lives in two files, they can start to disagree.
- conventions.md became an incident log. Most of its 202 KB Testing craft section was write-ups of past incidents: measurements, run counts, the same trap recounted once per spec that hit it. The rule itself was usually one sentence.
- The rule was already written down and still ignored. The project's conventions.md Scope paragraph said not to restate domain requirements and that a bullet grown into a retrospective has drifted. Close mode added content without checking against it.

Suggested changes
- Route content by type at close. The proposal should check each item against the split above before adding it:
  - requirements go through consolidation into specs/domains/, never into .speccraft/;
  - reasoning and write-ups go into the history entry;
  - conventions.md receives only rules that are not requirements;
  - architecture.md receives only edits to the package map, plus one Change log line of about 160 characters or less.
- Check for duplicates before adding. When a proposed conventions or architecture item repeats a domain requirement or history text, link to it rather than copying it.
- Consider dropping the architecture Change log. history.md already covers it; if it stays, have it generated from history rather than hand-written.