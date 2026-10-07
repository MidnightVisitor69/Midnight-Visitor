# Coordinator playbook (when Claude is offline)

For the dev, and for any agent the dev points here ("Read E:\AI\Waifu Card Game\pipeline\PLAYBOOK.md.
You are the Coordinator."). Good coordinator seats: OpenCode Desktop on `opencode/space-bunny-free`
(project folder `E:\AI\Waifu Card Game`), or Freebuff on a model WITHOUT the "may use data for AI
training" label. The D: drive is off limits to every agent, always.

## The system in one minute
- Five workers build in parallel, each in its own git worktree/branch, started by Windows scheduled
  tasks every 15 min (`pipeline/run.ps1 -Lane <lane>`):
  | Lane | Agent (rules file) | Queue folder | Branch / worktree |
  |---|---|---|---|
  | card (game code) | builder (`pipeline/BUILDER.md`) | `pipeline/tasks/` | pipeline / `E:\AI\waifu-pipeline-wt` |
  | motion + sound | animator (`ANIMATOR.md`) | `pipeline/tasks-motion/` | motion / `E:\AI\waifu-motion-wt` |
  | design / UI | designer (`DESIGNER.md`) | `pipeline/tasks-design/` | design / `E:\AI\waifu-design-wt` |
  | art (image pipeline) | artist (`E:\AI\Waifu Image Pipeline\ARTIST.md`) | `pipeline/tasks-art/` | pipeline / `E:\AI\waifu-art-wt` |
  | QA + fixes | Freebuff (`FREEBUFF_PROMPT.md`), kept going by `nudge.ps1` | its own loop | freebuff / `E:\AI\waifu-fb-wt` |
- Every task: `queue/` -> `active/` -> agent -> independent `verify.ps1` -> `review/` (passed) or
  `blocked/` (failed twice). With `pipeline/AUTO_MERGE` present, passed work merges into `main` by itself.
- Watchers: `Waifu Monitor` (read-only free agent, every 30 min -> `pipeline/MONITOR_REPORT.md`) and
  the job board (`pipeline/board.html`, rebuilt every minute; phone: http://100.122.252.80:8790 over
  Tailscale, served by `serve_board.py` with Python 3.11, NOT ComfyUI's Python: the firewall blocks that one).

## Daily check (5 minutes)
1. Board: anything red/STALLED/BLOCKED? 2. `MONITOR_REPORT.md` "Needs the dev". 3. `freebuff/LOG.md`.
4. Run the game: `E:\AI\Tools\Godot\Godot_v4.7.2-stable_win64.exe --path "E:\AI\Waifu Card Game\client"`.

## Adding work (the Coordinator's main job)
1. Talk the idea through with the dev. Check it against `AGENTS.md` (rules win).
2. Pick ONE lane (game logic -> card; animation/sound -> motion; look/layout/settings -> design;
   card art tooling -> art; bugs -> write the repro into `pipeline/freebuff/` notes or a card-lane task).
3. Write `<queue folder>/queue/<ID>-<slug>.md`. ID prefix by lane: T- card, M- motion, D- design,
   A- art; next free number (look in all subfolders). Tasks run in file-name order.
4. Use this template (copy an existing task for tone):
   ```
   # <ID>: <one-line goal>
   Requires: <worktree-relative files that must already exist on main>   (optional)
   ## Goal            what and why, with evidence
   ## Work only in    exact files/folders
   ## Do              numbered, concrete steps
   ## Tests           each behaviour with the exact assertion
   ## Fault injection for each guard: the break -> the test that must FAIL
   ```
   A test that passes whether or not the feature exists is worthless; say what must NOT change.

## Unsticking
- Pause everything: create `pipeline/STOP`. Resume: delete it. Freebuff nudges: `pipeline/STOP_NUDGE`.
- Task in `blocked/`: read its last section (verifier output + reason). Fix the spec, then move the
  file back to `queue/`. Failed work is kept on git tag `failed/<ID>`.
- Lane idle with a non-empty queue: its task may be waiting on `Requires:` files that aren't on main
  yet (merge or wait), or `pipeline/.cooldown-<lane>` exists (provider errors; delete it to retry).
- Merge conflict reported in a STATUS file: resolve in `E:\AI\Waifu Card Game` (main), commit.
- Undo a bad merge: `git log --oneline main`, then `git revert -m 1 <merge sha>`. Never push.
- Freebuff stopped: click its window and type the line from `FREEBUFF_PROMPT.md`'s first message.

## Models and money
- `pipeline/FREE_ONLY` present = every lane uses Space Bunny Free (then the second account if logged
  in). Delete it to go back to the paid chains in `run.ps1` (Kimi K3 / DeepSeek) when Go resets.
- Second opencode account: `$env:XDG_DATA_HOME='E:\AI\Tools\opencode-alt'; opencode auth login`.
- No local models: the GPU belongs to image renders.

## Steps only the dev can do
- Database (Supabase project `waifu-card-game`): agents have NO database access. To add approved
  cards: `node tools/import-cards.mjs shared/art/approved --alpha --banner kat-alpha --banner-name "KaT Alpha"`
  in `E:\AI\Waifu Card Game`, then paste the SQL file it prints into Supabase -> SQL Editor -> Run.
  To hide the old grey test cards: `update public.cards set active = false where set_id = 'test';`
- Approve art: look at `shared/art/inbox/_sheets/*.jpg`, move chosen card folders from
  `shared/art/inbox/` to `shared/art/approved/` and set `"approved": true` in their `card.json`.
- Phone build: `powershell -File tools\build_apk.ps1` (once task T-012 lands), phone plugged in.
- Anything that accepts terms, logs in, spends money, or changes security/firewall settings.

## Safety rules the Coordinator never breaks
No D: drive. No KaT private/explicit folders. Characters are adults; no franchise characters; no
school settings. No pushing, no force, no deleting history. AGENTS.md wins over everything here.
