# Builder rules (overnight card-game pipeline)

You are the headless builder. Nobody is watching while you work: there is no one to answer
questions, so never ask. When something is ambiguous, pick the simplest choice that obeys
AGENTS.md, do it, and write the choice under "Decisions" in your final report.

## Read first, every task
1. `AGENTS.md` (project rules: they override anything here except the safety rules below).
2. `.task.md` (your one task). Do that task and nothing else.

## Hard rules
- Work only inside this folder. Never touch anything outside it.
- Never edit: `AGENTS.md`, `opencode.json`, `pipeline/`, `shared/art/`, the existing
  `supabase/migrations/*.sql` files, `client/scripts/config.gd`, or the test harness files
  `client/tests/run_tests.gd`, `test_case.gd`, `screenshot.gd`.
- Never generate, download, or edit character art. The card pipeline only READS approved art.
  Placeholders must be procedural (gradients, shapes, noise drawn in code or shaders).
- No network calls to Supabase or anything else from tests. No secrets anywhere.
- No real person's name anywhere: code, comments, credits, commit messages.
- Content: characters are clearly adult; nothing beyond the AGENTS.md content rules.
- Git: commit on the current branch only. Stage files by name (`git add <paths>`), never
  `git add -A` or `git add .`. No push, reset, checkout, switch, merge, rebase, or amend.
  Commit message: `<TASK-ID>: <what changed>`.

## Godot
- Engine: `E:/AI/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (Godot 4.7, GDScript).
  Call it `$G` below. Project lives in `client/`.
- IMPORTANT: Godot exits 0 even when scripts fail to compile. Always read the output for
  `SCRIPT ERROR`, `Parse Error`, and `ERROR:` lines; zero of those is the bar.
- Import / compile check: `& $G --headless --path client --import`
- Unit tests: `& $G --headless --path client --script res://tests/run_tests.gd`
  Add tests as `client/tests/test_<feature>.gd` extending `res://tests/test_case.gd`; each
  `test_*` method is one test and must be synchronous (no `await`).
- Shaders are NOT compiled in headless mode. To check a shader scene, render it:
  `& $G --path client --position -4000,-4000 --resolution 540x960 --script res://tests/screenshot.gd -- res://scenes/<scene>.tscn <out_dir>`
  Use an out_dir outside git, e.g. `.shots/`. Look at the output for shader errors.
  A scene can expose `screenshot_count() -> int` and `screenshot_setup(i) -> String`
  so one run captures every variant.
- Before naming a method or property, check Godot's built-in classes don't already define it
  (`rpc`, `name`, `owner`, `get_*`...): overriding a native method is a compile error.
- Use typed GDScript. Comment WHY, not what. Keep files small.

## Tests are the deliverable
Every behaviour the task asks for needs a test that FAILS if the behaviour is removed.
A test that would pass either way is worthless. Before you finish, break each guard on
purpose, confirm its test fails, then restore it, and report each break in your final report.

## Finish
When the task is done and all checks are clean, commit. Your final message is your report:

```
## Report <TASK-ID>
Status: DONE | PARTIAL | STUCK
Files: <list>
Checks: import <clean|errors>, tests <N passed, M failed>, screenshots <paths or n/a>
Fault injection: <guard -> test that failed>, ...
Decisions: <anything you chose without being told>
Open questions for the dev: <or none>
```
If you cannot finish, commit only what compiles and passes, and report PARTIAL or STUCK
with the exact blocker. Never commit broken code to make a task look done.
