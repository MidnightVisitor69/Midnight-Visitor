# Overnight pipeline

opencode (DeepSeek V4.1 Flash, agent `builder`) builds one task at a time while we plan.
Claude reviews; nothing reaches `main` without Claude's review and the dev's OK.

## Where things are
| What | Where |
|---|---|
| At-a-glance status | `pipeline/STATUS.md` |
| Tasks | `pipeline/tasks/{queue,active,review,blocked,done}/` - the folder IS the status |
| Builder's work | branch `pipeline`, worktree `E:\AI\waifu-pipeline-wt` (never edit it by hand) |
| Logs | `pipeline/logs/` (`runner.log`, `<id>.attempt<N>.log`, `<id>.verify<N>.txt`) |
| Screenshots | `pipeline/shots/<id>/` (real-GPU renders of shader scenes) |
| Failed work | git tag `failed/<id>` (the branch is rolled back so the next task starts clean) |

## Flow
`queue/` -> `active/` -> builder -> `verify.ps1` (independent: import, unit tests, smoke run,
GPU screenshots, node tests, protected-file/secret/author guards) -> `review/` or, after one
retry, `blocked/`. Tasks run in file-name order, each on top of the last.

## Controls
- **Add work:** drop `T-NNN-slug.md` in `tasks/queue/` (template: any existing task).
- **Pause everything:** create an empty file `pipeline/STOP`. Delete it to resume.
- **Run now** instead of waiting for the 15-minute tick: `.\pipeline\run.ps1`
- **Scheduled task:** "Waifu Pipeline Runner" (Task Scheduler), hidden window via `run_hidden.vbs`.
- Provider/quota errors requeue the task and pause 60 min (`pipeline/.cooldown`).

## Review (Claude)
For each item in `review/`: read the diff (`git diff <base>..<commit>` from the result block),
look at the screenshots, run the checks yourself, then cherry-pick or merge into `main`
and move the task file to `done/`.
