# Freebuff: overnight QA + fix loop for the waifu card game

You are working ALONE overnight; the dev is asleep. Never stop to ask: decide, log the decision,
keep going. When a job is done, immediately start the next loop iteration. Stop only at 10:45 local
time or if the file `E:\AI\Waifu Card Game\pipeline\STOP` exists (check before every iteration).

## Where you work
- Your worktree: `E:\AI\waifu-fb-wt` (branch `freebuff`). Work ONLY there. Commit there, never push,
  never touch `main`, never `reset --hard`/`clean`/`checkout` other branches.
- Read first: `E:\AI\waifu-fb-wt\AGENTS.md`, `E:\AI\waifu-fb-wt\pipeline\BUILDER.md` (hard rules,
  Godot commands, test rules: all apply to you), `E:\AI\Waifu Card Game\pipeline\QA.md` and
  `E:\AI\Waifu Card Game\pipeline\FIXER.md` (read these two from the main checkout: they're newer).
- The D: drive is off limits, always. Never read KaT folders, anything nsfw/private/viv.
- Godot: `E:\AI\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`. Godot exits 0 even on script
  errors: read the output for `SCRIPT ERROR`, `Parse Error`, `ERROR:`.

## Loop (repeat until 10:45)
1. Bring in the other lanes' newest work: `git merge --no-edit pipeline`, then `motion`, then `design`
   (all local branches in this repo). If a merge conflicts: `git merge --abort`, skip that branch this
   round, note it in the log. Then run the unit tests.
2. First iteration only: build the QA harness exactly as `pipeline\QA.md` describes
   (`client/tests/qa/sweep.gd` with check ids, a fake API in `client/tests/fakes/`, journeys, UI audit:
   overlaps, blocked/dead/undersized buttons, off-screen/clipped, safe area for 1080x2400, animations
   end in the right state, skip works, nothing runs after leaving a screen; and the pack resilience
   crash tests from `pipeline\tasks-motion\*\M-002-pack-opening.md` "Resilience" once pack opening exists).
   Run it with `-- --only <id>` and `--include-known` support.
3. Sweep: run the whole harness. Write `E:\AI\Waifu Card Game\pipeline\freebuff\sweep-<N>.md`
   (table: check | screen | severity | result, then details).
4. Fix, most severe first (blocker -> major -> minor -> polish): for each failing check, root-cause it,
   make the smallest correct fix, add a regression unit test in `client/tests/test_*.gd` that fails
   without the fix (prove it), rerun ALL unit tests + the sweep, commit `FB-<N>-<NN>: <fix>`.
   A flow problem (a screen that doesn't make sense, not a bug) is NOT yours to redesign: describe it
   in `pipeline\freebuff\flow-issues.md` for the design lane.
5. Independent check after each round of fixes (PowerShell):
   `powershell -File "E:\AI\Waifu Card Game\pipeline\verify.ps1" -Worktree E:\AI\waifu-fb-wt -BaseRef <commit you started the round from> -ShotDir "E:\AI\Waifu Card Game\pipeline\shots\fb-<N>"`
   It must print `VERIFY: PASS`. If it fails, fix that before anything else.
6. Append one line per round to `E:\AI\Waifu Card Game\pipeline\freebuff\LOG.md`: time, sweep N,
   checks pass/fail, fixes committed, merges skipped, open problems. Then go to step 1.

## Content and safety
Characters are adults, clothed; no franchise characters; nothing from the image pipeline is yours.
No downloads, no installs, no network calls in tests, no secrets, no real names, stage files by name.
