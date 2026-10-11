# Handoff prompt — paste into a fresh coordinator session

> Read E:\AI\Waifu Card Game\pipeline\HANDOFF_PROMPT.md — you are the pipeline Coordinator.
> State below was verified 2026-10-10 23:05 CDT on the dev's PC. Resume from it; do not
> re-diagnose what is already diagnosed.

## What was done and verified today (2026-10-10)

1. **opencode was globally broken and is now fixed.** The shared `opencode.db` had a `workspace`
   table in the OpenCode-2 preview shape (provider/binding, no `project_id`), so every
   `opencode run` died instantly with `no such column: project_id` (anomalyco/opencode#42170).
   Fixed at 12:27 by recreating the V1 `workspace` table; original schema backed up at
   `C:\Users\vanna\.local\share\opencode\workspace_backup_20261010.sql`.
2. **Scheduler bug fixed**: the "Waifu Pipeline Runner" task had `ExecutionTimeLimit PT5M`
   (killed mid-task runs); raised to PT3H.
3. **`run.ps1` `Test-Ready` parser fixed** (still uncommitted): trailing prose after a
   `Requires:` path no longer makes a task wait forever.
4. **Branches reconciled**: lane branches rebuilt onto main after yesterday's rebase onto the
   orphan GitHub README history; merges are clean. T-015's `Requires:` fixed.
5. **Space Bunny Free daytime hang (2nd occurrence, ~12:24) managed**: all four lanes' builders
   hung with 0-byte logs (the documented Oct 7 quota pattern). Hung builders killed, actives
   returned to queue, cooldowns set to 18:30, monitor disabled to stop zombie pileup.
6. **EVENING RESUME CONFIRMED WORKING (~23:00)**: cooldowns expired, lanes resumed on their
   15-min schedules, and **T-010 (card importer) built, verified, and merged itself into main
   as `3e61392`** (AUTO_MERGE flag is present — passed work merges automatically, no human
   merge step needed).
7. **The four tasks whose runners were killed at midday (A-003, A-004, M-003, D-002) were
   requeued by hand at 23:04** — the runner had parked them in `blocked/` with "interrupted"
   notes. Also re-enabled the **Waifu Monitor** scheduled task (now `Ready`).
8. Roadmap: `pipeline/NEXT_STEPS.md` (Phases A–D, dev-only actions, watch items).

## Current live state (verified 23:05 CDT)

- **Active right now** (builders started ~22:49–23:18, healthy): card T-011 (export presets),
  motion M-004 (acquire moments), design D-003 (settings accessibility).
- Queues: card T-012…T-015 · art A-003, A-004 · motion M-003 · design D-002, D-004, D-005, D-006.
  qa/fix: empty (self-queues when main moves — needs the Freebuff worker, see below).
- Done: card T-000…T-010 (+B-001), motion M-001/M-002, design D-001, art A-001/A-002.
  Interrupted work preserved on git tags `interrupted/<ID>`; main tip `3e61392`.
- No cooldowns, no STOP flag, `FREE_ONLY` present (all lanes on Space Bunny Free).
- Uncommitted: `AGENTS.md`, `pipeline/PLAYBOOK.md`, `pipeline/FREEBUFF_PROMPT.md` (the dev's
  own edits — leave them), `pipeline/run.ps1` (the Test-Ready fix — should be committed),
  and untracked docs (`MORNING.md`, `TAKEOVER.md`, `agent-gaps-spec.md`,
  `price-sheet-draft.md`, `NEXT_STEPS.md`, this file, `shared/art/`).

## What needs fixing / deciding

**Coordinator (next session):**
1. Confirm the 23:04 requeues got picked up (art lane fires A-003 on its next 15-min tick;
   check `pipeline/STATUS-art.md` and `pipeline/logs/runner*.log` for a fresh "attempt 1"
   with non-zero output).
2. Commit the `run.ps1` Test-Ready fix (and optionally the pipeline docs) on main.
3. Watch for the next daytime Space Bunny hang (pattern: 0-byte builder logs). If it happens
   again, apply the same hold (`.cooldown-<lane>` files + kill the `run --agent` processes +
   requeue actives) — then ask the dev whether to switch daytime lanes to the spend ladder
   (delete `pipeline/FREE_ONLY` = Kimi K3 / DeepSeek per run.ps1).
4. Accepted-risk: the opencode DB fix breaks again if an OpenCode 2 preview touches
   `opencode.db`; re-apply the DDL from the backup file's header if `no such column:
   project_id` returns.

**Dev decisions/actions (nothing blocks the queue on these):**
1. **T-010 has landed — the 62 KaT alpha card import is now unblocked**: run
   `node tools/import-cards.mjs shared/art/approved --alpha --banner kat-alpha
   --banner-name "KaT Alpha"` in `E:\AI\Waifu Card Game`, paste the printed SQL into
   Supabase -> SQL Editor -> Run, then
   `update public.cards set active = false where set_id = 'test';` (PLAYBOOK §dev-only).
2. Approve `pipeline/price-sheet-draft.md` — unlocks coded prices and T-015 reward amounts.
3. Restart the Freebuff QA worker (Windows Terminal tab at `E:\AI\waifu-fb-wt`, paste the
   first message from `pipeline/FREEBUFF_PROMPT.md`) — unblocks QA sweeps.
4. Approve art sheets in `shared/art/inbox/_sheets/`, move picks to `shared/art/approved/`.
5. After T-011+T-012 land: build/install the APK on the Pixel 6 (`tools\build_apk.ps1`).
6. Spend decision: delete `pipeline/FREE_ONLY` for the dev's "$3 DeepSeek cap then Space
   Bunny" ladder — dev-only call, unurgent while free model keeps working at night.

Full roadmap: `pipeline/NEXT_STEPS.md`. Rules: AGENTS.md wins; never touch D:; nothing pushes.
