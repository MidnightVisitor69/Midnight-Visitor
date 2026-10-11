# TAKEOVER: you are now the Coordinator (Claude is out of usage for the week)

Read this whole file, then `pipeline/PLAYBOOK.md` (how the system works and how to unstick it), then
`AGENTS.md` (project law). You replace Claude as architect, reviewer and overseer of an overnight
multi-agent pipeline building a Godot 4 mobile card game ("Waifu Card Collector") with a Supabase
backend. The dev ("Vyn") is non-technical-ish, works with you in chat, and is often away or asleep.

## Your job, in priority order
1. Keep the workers moving: check the board / STATUS files / logs, merge verified work, requeue
   blocked work with a clear BUILDER NOTE, fix pipeline jams. Never let one stuck task idle a lane.
2. Review what lands: read the task's report + verify output + diff, LOOK at screenshots in
   `pipeline/shots/<ID>/`. "Verified" only means it compiles and tests pass, not that it's DONE:
   check the task's list of deliverables actually exists (M-001 once "passed" with 1 of 6 files).
3. Turn the dev's ideas into task files in the right lane queue (template in PLAYBOOK.md).
4. Do the steps workers can't, or hand them to the dev (database, phone build, art approval).
5. Be honest with the dev: say what's done, what isn't, and what looks bad.

## State on 2026-10-07 ~08:30 (verify; things moved since)
- main has: Godot client (sign-in anonymous, app shell, Home tab with odds/pity, trade tab, holo card
  tiers + 5 holo shaders + holo test scene), manifest validator, job board (`tools/board/`),
  80 unit tests green. Server: get_home, get_banners, get_set_sizes, alpha_grant_gems,
  delete_my_account live on Supabase (agents have NO DB access).
- Image pipeline repo `E:\AI\Waifu Image Pipeline` main has: layer tools, render engine + WD14
  safety gate. 62 KaT alpha cards are in `shared/art/approved/` (from her closet/daily pictures).
- Queued/active: card T-008 (collection), T-010 importer, T-011 export presets, T-012 build_apk
  script; motion M-001 (sound kit, requeued: unfinished), M-002 pack opening (+resilience), M-003,
  M-004; design D-001..D-006 (D-002 has notes about square legendary particles and a holo glare
  over the character: fix those); art A-003 (7 set shot lists), A-004 (QC loop via kat-qc).
- After A-003 merges: register a scheduled task 'Waifu Art Render' running the image repo's
  `run_render.ps1` (read it first) so the 7 themed sets render into `shared/art/inbox/`.
- Modes: `pipeline/FREE_ONLY` (all lanes on Space Bunny Free), `pipeline/AUTO_MERGE` (verified work
  merges into main). Task time limit 120 min.

## Lessons learned (don't repeat Claude's mistakes)
- Running Godot `--import` in the MAIN checkout creates `.import`/`.uid` files that block auto-merge
  ("CONFLICTED" in runner logs). Test in a worktree, or delete untracked generated files before merging.
- Godot exits 0 on script errors: always grep output for `SCRIPT ERROR|Parse Error|ERROR:`.
- PowerShell 5.1: native stderr + `$ErrorActionPreference='Stop'` = fake failures; `"$id:"` is a parse
  error (use `${id}`); `Set-Content` without `-Encoding utf8` mangles `·`; `-join` binds looser than `+`.
- The nudge (`E:\KaT_Exchange\nudge.ps1`) can't type into Freebuff while another window has focus
  (Windows blocks focus steals). It only works while Freebuff's window is in front.
- ComfyUI's bundled Python is firewall-BLOCKED on purpose; serve anything on the network with
  Python 3.11 (`C:\Users\vanna\AppData\Local\Programs\Python\Python311\python.exe`).
- CardView re-lays itself out each frame; external size/scale is ignored (D-002 asks for an API).

## Hard rules (the dev's, non-negotiable)
- The D: drive is off limits to every agent, always.
- Never touch KaT's private/explicit folders (`_wf_tmp`, `nsfw`, `mature_art`, `kohya`, `private_*`, `viv_*`).
- Never push, force, reset main, or delete history. Never enter passwords, keys, payment details, or
  accept terms: hand those to the dev. Never use models labeled "may use data for AI training".
- No real names in code/commits (git author is `waifu-dev`). Ask the dev before anything that costs money.

## Where to look
Board: `pipeline/board.html` (phone: http://100.122.252.80:8790 via Tailscale) · `pipeline/MONITOR_REPORT.md`
· `pipeline/STATUS*.md` · `pipeline/logs/runner*.log` · `pipeline/tasks*/{queue,active,review,blocked,done}`
· Freebuff QA log `pipeline/freebuff/LOG.md` · nudge `pipeline/logs/nudge.log`.

## EVERYTHING Claude was running and controlling (you control all of it now)

### Windows scheduled tasks (Task Scheduler; all run as Vyn, hidden windows)
| Task | Every | Runs | Control |
|---|---|---|---|
| Waifu Pipeline Runner | 15 min | `pipeline\run_hidden.vbs` -> `run.ps1 -Lane card` | builder agent, queue `tasks\` |
| Waifu Motion Lane | 15 min | `run_hidden_motion.vbs` -> `-Lane motion` | animator agent, `tasks-motion\` |
| Waifu Design Lane | 15 min | `run_hidden_design.vbs` -> `-Lane design` | designer agent, `tasks-design\` |
| Waifu Art Lane | 15 min | `run_hidden_art.vbs` -> `-Lane art` | artist agent, `tasks-art\` |
| Waifu Monitor | 30 min | `run_hidden_monitor.vbs` -> `monitor_run.ps1` | read-only monitor -> `MONITOR_REPORT.md` |
| Waifu Board | 1 min | `run_hidden_board.vbs` -> `board_run.ps1` | regenerates `board.html` (no model) |
| Waifu - re-enable KaT GPU jobs | once, 12:00 | re-enables 'KaT Explicit Night' + 'KaT Explicit Video' | Claude DISABLED those two for the card-art night; this puts them back, then deletes itself |
| Waifu Art Render | (not yet) | create after A-003 merges: `E:\AI\Waifu Image Pipeline\run_render.ps1` every 30 min | renders the 7 themed sets |
PowerShell: `Get-ScheduledTaskInfo -TaskName '<name>'` (health), `Start-ScheduledTask` (run now),
`Disable-ScheduledTask` / `Enable-ScheduledTask` (pause one lane). Run any lane by hand:
`powershell -File "E:\AI\Waifu Card Game\pipeline\run.ps1" -Lane <card|motion|design|art>`.
`run.ps1` also supports lanes `qa` and `fix`, but their agents were never created (a safety classifier
blocked it) and they have no scheduled tasks: Freebuff does QA instead.

### Background processes (not scheduled; die on reboot; restart them by hand)
- Freebuff QA loop: a Windows Terminal tab running `freebuff` in `E:\AI\waifu-fb-wt` (branch
  `freebuff`), prompt `pipeline\FREEBUFF_PROMPT.md`, model GLM 5.3 Flash max. Its work is NOT
  auto-merged: review `git log main..freebuff` and merge it into main yourself when it's good.
- Nudge: `powershell -File E:\KaT_Exchange\nudge.ps1 -Worktree E:\AI\waifu-fb-wt -TitleMatch Freebuff
  -IdleSeconds 420 -MaxNudges 40 -StopFile "E:\AI\Waifu Card Game\pipeline\STOP_NUDGE"
  -LogFile "E:\AI\Waifu Card Game\pipeline\logs\nudge.log" -Prompt "<continue line>"` (hidden).
- Board web server: Python 3.11 running `pipeline\serve_board.py 8790` (serves only board.html).

### Flags (empty files in `pipeline\`)
`STOP` pauses every lane · `STOP_NUDGE` stops the nudge · `FREE_ONLY` all lanes free-only ·
`AUTO_MERGE` verified work merges into main · `.cooldown-<lane>` lane paused after provider errors
(delete to retry) · `.model-offset-<lane>` current position in the lane's model chain (delete to reset).

### Agents and their rules (opencode, defined in `E:\AI\Waifu Card Game\opencode.json`)
builder (`pipeline\BUILDER.md`), animator (`ANIMATOR.md`), designer (`DESIGNER.md`), monitor
(`MONITOR.md`, read-only). artist lives in `E:\AI\Waifu Image Pipeline\opencode.json` (`ARTIST.md`).
Image QC (A-004) reuses the dev's global `kat-qc` agent (`~\.config\opencode\agent\kat-qc.md`, Kimi K3).
Model chains are the `$Lanes` table at the top of `pipeline\run.ps1` (edit there). Second opencode
account login lives in `E:\AI\Tools\opencode-alt` (used via `alt|<model>` chain entries once logged in).
Global opencode config `~\.config\opencode\opencode.json` has a D: deny Claude added (backup beside it).

### Repos, branches, worktrees
Game repo `E:\AI\Waifu Card Game` (main) with worktrees: `E:\AI\waifu-pipeline-wt` (pipeline),
`waifu-motion-wt` (motion), `waifu-design-wt` (design), `waifu-fb-wt` (freebuff). Image repo
`E:\AI\Waifu Image Pipeline` (main) + `E:\AI\waifu-art-wt` (pipeline). Failed/interrupted work is on
tags `failed/<ID>`, `interrupted/<ID>`. Never edit inside a worktree while its lane is running.

### Verifiers and guards (the safety net; don't weaken them)
`pipeline\verify.ps1` (Godot import, unit tests, smoke run, GPU screenshots, node tests, audio guard,
protected files, no art/images, no secrets, anonymous author), `verify-art.ps1` (image repo: content
guards on set files, rating ladder), `check_audio.py` (loudness/pitch/click limits).

### Tools and services
Godot 4.7.2 `E:\AI\Tools\Godot\` · Android SDK `E:\AI\Tools\Android\sdk` (adb in `platform-tools`) ·
JDK 17 `E:\AI\Tools\jdk17` · debug keystore `E:\AI\Tools\Android\debug.keystore` · export templates in
`%APPDATA%\Godot\export_templates\4.7.2.stable` · depth + cut-out models in `E:\AI\ComfyUI\models\`
(`depth\Depth-Anything-V2-Small-hf`, `rembg\isnet-anime.onnx`) · ComfyUI picture tool
`E:\AI\ComfyUI\_scripts\oc_media.py` (renders wait their turn on the shared GPU) · Supabase project
`waifu-card-game` ref `uombscvrcpjrlbypwcuk` (dev-only access; anonymous sign-in is ON; `app_config`
row `alpha_mode`=true enables the +1600 alpha gem button; turn off before any public build) ·
Phone: Pixel 6 (USB debugging authorized for this PC) · Tailscale PC address 100.122.252.80.

### Claude's own check-in routine (now yours)
Every ~30 min: (1) health of every scheduled task + nothing in an `active\` folder over 130 min,
(2) grep newest logs for forbidden targets (D:, KaT private folders, push/reset/curl), STOP if an
agent tried one, (3) review + merge what's in `review\` folders, requeue `blocked\` with a BUILDER
NOTE, (4) after A-002/A-003 set up the render task, (5) integration: T-010 importer -> dev pastes SQL;
T-011/T-012 -> `tools\build_apk.ps1` with the phone plugged in, (6) keep `pipeline\MORNING.md` current.
Full detail: `pipeline\CHECKIN.md`.

## Start now
1. Read the board and every STATUS file; list what's active, blocked, waiting in review.
2. Merge anything verified that auto-merge left in review (check `git status` on main first).
3. Report to the dev in 10 lines: what's running, what's stuck, what you're doing next, what they must do.
