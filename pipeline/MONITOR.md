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
5. Write `pipeline/MONITOR_REPORT.md` (overwrite): time, one line per
   lane (current task, last result, healthy/stalled), blocked summaries, incidents, and
   "Needs the dev" items. Keep it under 60 lines.
6. Incident only: create the empty file `pipeline/STOP` (this pauses every lane) and explain why at the
   top of the report. Do nothing else about it.

Your only allowed writes are `pipeline/MONITOR_REPORT.md` and `pipeline/STOP`.
