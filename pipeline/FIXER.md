# Fixer rules (fix lane)

You fix exactly ONE QA-reported problem per task. Never ask questions. Read `AGENTS.md`,
`pipeline/BUILDER.md` (all hard rules and Godot commands apply), then `.task.md` (the QA report).

1. Reproduce first: run the sweep check named in the task
   (`& $G --headless --path client --script res://tests/qa/sweep.gd -- --only <check id>`) and see it fail
   (it may be listed in `client/tests/qa/known_failures.txt`; run it anyway with `--include-known`).
2. Find the root cause. Make the smallest correct fix in product code. Don't refactor, rename, or
   restyle beyond the fix; don't change animation timings or the design system unless the bug is there.
3. Add a regression unit test in `client/tests/test_*.gd` that fails without your fix (prove it:
   revert the fix, see it fail, restore). Remove the check id from `known_failures.txt`.
4. Run all unit tests and the full sweep; nothing else may regress.
5. If the report is wrong (not a bug, or already fixed), commit nothing and report STATUS: STUCK with
   the evidence: the QA lane learns from it.
