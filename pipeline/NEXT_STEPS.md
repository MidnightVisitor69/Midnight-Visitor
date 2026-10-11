# Next steps for the whole project (Coordinator's roadmap, 2026-10-10)

Written after the 2026-10-10 pipeline repair. Every "done" below was verified on this machine
today; everything unchecked has an owner and a trigger. Read together with
`agent-gaps-spec.md` (the decision record) and `PLAYBOOK.md` (how the lanes work).

---

## 0. Where things stand right now (verified today)

**Repaired today (was silently broken for days):**
- **opencode was dead.** The shared `opencode.db` had a `workspace` table in the OpenCode-2
  preview shape (no `project_id` column), so every `opencode run` died instantly with
  `no such column: project_id` (known issue: anomalyco/opencode#42170). Fixed at 12:27 by
  recreating the V1 `workspace` table; backup at
  `C:\Users\vanna\.local\share\opencode\workspace_backup_20261010.sql`.
  If it ever returns (an OpenCode 2 preview touching the DB), re-apply that DDL.
- **The scheduled task killed every build at 5 minutes** (`ExecutionTimeLimit: PT5M`). Raised
  to `PT3H`. This alone made real tasks impossible.
- **Lane branches couldn't merge into main** (yesterday's rebase onto the orphan GitHub README
  history). Card/design/motion lanes reconciled onto main; merges are clean again.
- **`Test-Ready` parser bug** in `run.ps1` fixed (trailing prose after a `Requires:` path no
  longer makes a task wait forever).
- **All blocked tasks requeued.** Card queue is T-010 (building now) + T-011…T-015, zero
  blocked; every `Requires:` verified present on the pipeline branch.

**All five lanes are alive and building:** card `T-010`, motion `M-003`, design `D-002`,
art `A-003`. QA (Freebuff) is the only idle worker — see the dev list below.

---

## Phase A — Pipeline drains (automatic, no dev needed)

- [x] Repair opencode + scheduler + branches; requeue blocked work (2026-10-10)
- [ ] Card lane finishes `T-010` (importer) → `T-011` (export presets) → `T-012` (APK script) →
  `T-013` (soft pity) → `T-014` (wonder-trade locks) → `T-015` (ad stub). Six tasks, each
  verified by `verify.ps1` before it lands in `review/`.
- [ ] Coordinator reviews `review/` items and merges them into `main` (PLAYBOOK rule; the dev
  can also create `pipeline/AUTO_MERGE` to let verified work self-merge).
- [ ] Motion `M-003`/`M-004`, design `D-002`…`D-006`, art `A-003`/`A-004` finish and land the
  same way.
- [ ] First QA sweep (`Q-001`) auto-queues once main moves — **but only after the Freebuff QA
  worker is restarted** (dev action B2). Until then, sweeps will pile up unstarted; that is
  fine, they are capped at 12.
- [ ] Batched builder "open questions for the dev" from every review report get collected into
  one list (spec §2) — the Coordinator does this as reports arrive.

## Phase B — What only the dev can do

1. **Approve the price sheet** (`pipeline/price-sheet-draft.md`): reply "approved" in chat or
   edit numbers. Unlocks coding of real gem/pass/ad prices, streak-repair costs, and the
   `rewards` amounts in `T-015` (structure lands first; amounts stay placeholders until this).
2. **Restart the Freebuff QA worker**: click its Windows Terminal tab (worktree
   `E:\AI\waifu-fb-wt`) and paste the first message from `pipeline/FREEBUFF_PROMPT.md`.
   Unblocks QA sweeps and the exploit-checklist lane later.
3. **Approve art**: review `shared/art/inbox/_sheets/*.jpg`; move chosen card folders to
   `shared/art/approved/` and set `"approved": true` in each `card.json`.
4. **Import the 62 KaT alpha cards into Supabase** (agents have no DB access): once `T-010`
   lands, run `node tools/import-cards.mjs shared/art/approved --alpha --banner kat-alpha
   --banner-name "KaT Alpha"` in `E:\AI\Waifu Card Game`, paste the printed SQL into the
   Supabase SQL editor, then run
   `update public.cards set active = false where set_id = 'test';`.
5. **Play it on the Pixel 6** (after `T-011` + `T-012` land): plug the phone in and run
   `powershell -File tools\build_apk.ps1`. The phone is the look bar (spec §2) — judge polish
   there, not on PC screenshots.
6. Optional: log in the second opencode account for fallback capacity
   (`$env:XDG_DATA_HOME='E:\AI\Tools\opencode-alt'; opencode auth login`).
7. Optional: accept the agreed AGENTS.md edit (§8 of the spec — soften the Figma-first rule for
   the prototype phase).

## Phase C — Content and design milestones (coordinator queues, lanes build)

- [ ] **Battle design doc** (`T-016`, docs-only, queued when the card queue drains): 2–3
  mechanic options with tradeoffs mapped to existing tables (spec §4). Dev reacts whenever.
- [ ] **Server-published config**: holo odds, set sizes, pity ramp parameters read from the
  server; client shows what the server publishes (spec §3.1/§9.2 — `T-013` covers pity; verify
  no duplicated constants remain).
- [ ] **All 7 themed sets rendered → approved → imported** (8 cards each, Con Weekend 16).
  This is the launch-content gate; nothing ships publicly until it is done.
- [ ] **Character names** ("KaT · <moment>" is alpha-only): agents draft adult, non-real names
  once sets are approved; dev approves before any public build (spec §5).
- [ ] **Streak freeze/repair rules** coded per the price sheet once approved (§3.5).

## Phase D — Phase 1 → Phase 2 gate (before battles start)

- [ ] Coordinator runs the written exploit checklist: double-pull races, ledger mismatch,
  streak abuse, trade escrow races, idempotency replay, SSV forgery (spec §2).
- [ ] Dev plays a full session on the Pixel 6 and signs off.
- [ ] Both pass ⇒ Phase 1 done; battle work (design doc already approved) can start.

## Watch items / risks

- **Space Bunny Free daytime quota**: historically hung unattended 06:05–18:29 and recovered by
  evening. It happened again 2026-10-10 (all four lanes' builders hung with 0-byte logs through
  the afternoon). The Coordinator held every lane on `.cooldown*` files until 18:30 and requeued
  the affected tasks (T-010, A-003, M-003/M-004, D-002/D-003). `Waifu Monitor` was disabled
  during the hold to stop zombie process pileup — **re-enable it when the lanes resume**
  (`Enable-ScheduledTask -TaskName 'Waifu Monitor'`). If daytime throughput matters, the dev's
  own 10-07 ladder ("$3 DeepSeek cap then Space Bunny") can be re-enabled by deleting
  `pipeline/FREE_ONLY` — that is a spend decision for the dev only.
- **opencode.db is shared with the desktop app.** If a preview build re-migrates the workspace
  table, `no such column: project_id` returns — re-apply the DDL from
  `workspace_backup_20261010.sql`'s header.
- **3h task kill**: a build longer than 3 hours dies with the rest of the run (rare; requeued
  as interrupted).
- **AUTO_MERGE is off**: verified work waits in `review/` until the Coordinator merges or the
  dev creates the flag.

## How we proceed from here

Nothing needs the dev right now for the queue to move — all five lanes build unattended. The
next human touchpoints, in order of when they'll matter: **price sheet approval** (unlocks
economy values), **art sheets** (unlocks the real collection), **Pixel playtest after the APK
script lands**. The Coordinator keeps merging verified work, requeues failures with notes, and
pings the dev when a batch is ready (per the agreed "ping when ready" cadence).
