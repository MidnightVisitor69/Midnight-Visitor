# Claude's overnight check-in (followed every :13 and :43)

Dev asleep; target: working prototype on PC + Pixel 6 by 11:00. Be TOKEN-LEAN: the dev is low on
Claude usage. Delegate real work to the lanes as task files; I only check, review briefly, merge,
and do what agents can't (DB, scheduled tasks, APK). Never touch D:.

Lanes: card (tasks/, branch pipeline, wt E:\AI\waifu-pipeline-wt), motion (tasks-motion/, branch
motion, wt E:\AI\waifu-motion-wt), design (tasks-design/, branch design, wt E:\AI\waifu-design-wt),
art (tasks-art/, image repo E:\AI\Waifu Image Pipeline branch pipeline, wt E:\AI\waifu-art-wt).
Scheduled tasks: 'Waifu Pipeline Runner', 'Waifu Motion Lane', 'Waifu Design Lane',
'Waifu Art Lane', later 'Waifu Art Render'. The dev wants it to look FINISHED, not grey-box: judge
screenshots against pipeline/DESIGNER.md and queue design fix tasks when something looks cheap.
Merge order matters: design restyles what card/motion build; merge card+motion first, then design.

1. HEALTH: each scheduled task LastTaskResult 0 and ran <20 min ago; tails of logs/runner*.log;
   nothing in any */active older than 70 min; .cooldown; RAM, nvidia-smi, free disk on E:.
   Fix broken pipeline scripts on main (commit).
2. SAFETY: grep the newest logs for permission denials or forbidden targets (D:, _wf_tmp, nsfw,
   mature_art, kohya, private_, viv_, push, reset, curl). Anything intrusive -> create pipeline/STOP,
   stop renders, note it in MORNING.md.
3. REVIEW + MERGE (card and motion): per new review item: builder report + verify output, skim the
   diff, glance at 1-2 screenshots in pipeline/shots/<id>. Sound -> `git merge --no-ff <branch>`
   into main from E:\AI\Waifu Card Game, move the task to done/. Flawed -> queue a focused fix task
   in that lane. If merging the two lanes conflicts, resolve on main (prefer the motion lane for
   animation/sound files, the card lane for data/API files) and rerun the Godot tests on main.
4. ART: same review/merge into the image repo's main. After A-002 merges: read run_render.ps1,
   register 'Waifu Art Render' (every 30 min, hidden vbs, single instance), start it. After A-003:
   spot-check set files obey the brief.
5. RENDERS: tail out/render.log (image repo); per-set pass/reject counts; look at <=4 newest
   inbox/_sheets images per check-in. Unsafe output -> STOP + stop render task.
6. INTEGRATION: (a) A-001 done + T-010 merged -> in main checkout run
   `node tools/import-cards.mjs shared/art/approved --alpha --banner kat-alpha --banner-name "KaT Alpha"`,
   read the SQL, apply as a migration (Supabase project uombscvrcpjrlbypwcuk), set active=false
   where set_id='test', verify with a rolled-back DO-block pull from kat-alpha. (b) T-011 merged +
   E:\AI\Tools\setup_android.log has ANDROID SETUP DONE -> Godot editor settings (SDK
   E:\AI\Tools\Android\sdk, JDK E:\AI\Tools\jdk17, debug keystore E:\AI\Tools\Android\debug.keystore
   androiddebugkey/android), `--import`, `--export-debug "Android"` and "Windows Desktop",
   adb install -r on the Pixel (E:\AI\Tools\Android\sdk\platform-tools\adb.exe), launch, wait 15 s,
   screencap to pipeline/shots/phone/, confirm sign-in + Home. Re-export after later merges.
7. BUDGET: ~ $0.10/DeepSeek task, ~ $0.30/Kimi task unless better data. Past ~$8 total tonight ->
   set every lane's Model in run.ps1 to opencode/space-bunny-free (dev's choice); note it.
8. MORNING.md: playable status + how to launch (PC, phone), per-set art status + sheet paths,
   verdicts, safety events, what needs the dev, costs. At/after 10:45: stop renders, final
   integration + APK, then SendUserFile MORNING.md (status proactive).
Chat output: one line unless the dev must act.
