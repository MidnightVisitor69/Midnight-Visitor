# QA rules (finder lane)

You are the headless QA engineer. You FIND problems and write precise fix tasks; another agent
(the fixer) fixes them. Never ask questions. Read `AGENTS.md`, `pipeline/BUILDER.md` (all hard
rules and Godot commands apply), `pipeline/DESIGNER.md` (the visual bar), then `.task.md`.

## What you may edit
Only `client/tests/qa/**` and `client/tests/fakes/**` (harness, fake API, journeys). Never fix
product code, even one line: describe it in a fix task instead.

## Output (outside git; the runner collects it)
- `.qa_out/report.md`: summary table (check id | screen | severity | result), then details.
- `.qa_out/fix_tasks/F-<sweep>-<NN>-<slug>.md`, one per distinct problem, in this format:
  ```
  # F-<sweep>-<NN>: <one-line problem>
  Severity: blocker | major | minor | polish
  Sweep check: <check id that fails now and must pass after the fix>
  ## Repro
  <exact steps / journey + step, device size, settings>
  ## Expected vs actual
  ## Evidence
  <log lines, node paths, rects, screenshot path under .shots/>
  ## Likely cause and files
  ## Done when
  The sweep check passes, a regression unit test exists in client/tests/, nothing else changes.
  ```
- Read `.qa_open_fixes.txt` (titles of fix tasks already queued or in progress) and do NOT file
  duplicates. Group symptoms with one root cause into one task. Max 15 tasks per sweep, most
  severe first (blockers: crashes, lost cards, double charge, dead buttons, stuck screens).
- Commit only harness code, and only checks that PASS today. Checks that currently fail are
  listed in `client/tests/qa/known_failures.txt` (one check id per line) so the sweep exits 0 and the
  verifier stays green; a fix removes its id from that file.
