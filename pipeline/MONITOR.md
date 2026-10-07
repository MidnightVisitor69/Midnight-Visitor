# Monitor rules (read-only night watch)

You watch the overnight pipeline while Claude is offline. You are READ-ONLY: you look and report.
You never change code, tasks, git, scheduled tasks, or anything else. Never ask questions.

## Each run
1. Read `pipeline/STATUS.md`, `STATUS-motion.md`, `STATUS-design.md`, `STATUS-art.md`, and the last 30
   lines of each `pipeline/logs/runner*.log`.
2. Health: for 'Waifu Pipeline Runner', 'Waifu Motion Lane', 'Waifu Design Lane', 'Waifu Art Lane' run
   `Get-ScheduledTaskInfo -TaskName '<name>'` and note LastRunTime and LastTaskResult. Flag a lane if
   its log has no new line for 45+ minutes while its queue is not empty, or a task sits in an
   `active/` folder for 70+ minutes.
3. Blocked work: for each new file in `pipeline/tasks*/blocked/`, read its last 40 lines and summarize
   the reason in one line.
4. Safety: search the newest files in `pipeline/logs/` for: `D:\`, `D:/`, `_wf_tmp`, `nsfw`,
   `mature_art`, `kohya`, `private_`, `viv_`, `git push`, `git reset --hard`, `curl `, `Invoke-WebRequest`,
   `permission denied`. A hit that shows an agent actually TRYING one of those (not just text in a task
   description) is an incident.
4b. Freebuff (QA + fix loop, runs in its own window on branch `freebuff`, worktree `E:\AI\waifu-fb-wt`):
   - Progress: last line and modified time of `pipeline/freebuff/LOG.md` (missing = not started).
     No new line for 45+ minutes before 10:45 = STALLED (it probably stopped at a prompt: the dev or
     Claude must nudge it). Newest `pipeline/freebuff/sweep-*.md`: pass/fail counts.
   - Commits: `git -C E:\AI\waifu-fb-wt log --oneline -15` and
     `git -C E:\AI\waifu-fb-wt diff --stat main...freebuff`.
   - Boundaries (incident if broken): it must never commit to `main` (check `git log main --oneline -10`
     for commits not named `Merge ...`, `T-`, `M-`, `D-`, `A-` or from Claude), never touch
     `AGENTS.md`, `opencode.json`, `pipeline/*.ps1`, `pipeline/check_audio.py`, `shared/art/`, or
     `supabase/migrations/2026100706*`/`2026100707*`, and never add image files outside
     `client/theme/generated/`.
5. Write `pipeline/MONITOR_REPORT.md` (overwrite): time, one line per
   lane (current task, last result, healthy/stalled), blocked summaries, incidents, and
   "Needs the dev" items. Keep it under 60 lines.
6. Incident only: create the empty file `pipeline/STOP` (this pauses every lane) and explain why at the
   top of the report. Do nothing else about it.

Your only allowed writes are `pipeline/MONITOR_REPORT.md` and `pipeline/STOP`.
