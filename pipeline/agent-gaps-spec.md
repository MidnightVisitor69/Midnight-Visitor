# Spec: agent gaps — what must be fleshed out for the agents to keep working

Written 2026-10-07 (evening) by the Coordinator (Freebuff/GLM) from a 5-round interview with the
dev ("Vyn"). This file is the **authoritative record of decisions made in chat**. Where it
contradicts nothing in AGENTS.md, it extends AGENTS.md; where AGENTS.md and this file disagree,
AGENTS.md still wins until the dev edits it (see §8 for the one agreed edit).

Purpose: every "tune later", "ask the dev", or underspecified number that blocks or slows a lane
is listed here with its status. The Coordinator turns the actionable rows into lane task files
(template in PLAYBOOK.md) — this file is the source, not the tasks themselves.

---

## 1. Where the dev wants more information to flow (all four selected)

1. **Economy + monetization** — concrete numbers (holo odds, pity, prices, ad rewards).
2. **Art + set content** — what each themed set must contain; naming; approval flow.
3. **UI look + behavior** — what "finished, not grey-box" means per screen.
4. **Battle design (Phase 2)** — draft doc only, no code/schema (see §4).

## 2. Process rules confirmed in the interview

| Topic | Decision |
|---|---|
| Builder "Open questions for the dev" | **Batch to a list.** Builders keep coding around open questions; the Coordinator collects them and hands the dev one combined list. Nothing blocks on the dev. (Triggers: task reports under `pipeline/tasks*/review|done`.) |
| Phase 1 → Phase 2 gate | **Written exploit checklist + dev sign-off.** The Coordinator runs a checklist (double-pull races, ledger mismatch, streak abuse, trade escrow races, idempotency replay, SSV forgery) AND the dev plays on the Pixel 6. Both pass ⇒ Phase 1 done. |
| Dev review cadence | **Ping when ready.** Coordinator messages the dev whenever a batch is ready (APK, price sheet, art sheets). No fixed schedule. |
| Alpha flags (`app_config.alpha_mode`, test cards) | **Off before the APK leaves the dev's own hands.** Fine on the dev's personal Pixel; both must be off before the build goes to anyone else or to Play. Coordinator's standing reminder in every phone-build check-in. |
| Freebuff QA branch | **Coordinator auto-merges.** QA work (branch `freebuff`, NOT covered by AUTO_MERGE) is reviewed by the Coordinator — boundaries, diff, sweep log — and merged into main by the Coordinator when the sweep passes. Dev sees it in the log; no per-merge approval. |
| Card naming | **'KaT · <moment>' is alpha-only.** Before any public build, agents draft proper character names (adult; franchise/fictional names allowed, no real names) for dev approval. |
| Launch content | **All 7 themed sets** (8 cards each, Con Weekend 16). Nothing ships publicly until all are rendered, approved, and imported. |
| Look bar | **The Pixel 6 is the bar.** PC screenshots get only obvious-defect judging; batch look-polish decisions for phone sessions. (Supersedes over-eager screenshot-judging fix tasks.) |
| Figma-first rule | **DESIGNER.md wins for the prototype phase.** D-lane keeps coding screens from DESIGNER.md + `tokens.tres`; the Figma-first rule in AGENTS.md activates only when the dev populates the Figma file. AGENTS.md edit agreed in principle — see §8. |
| Play developer account | **No rush.** No account, no deadline. Target is a great APK on the dev's Pixel first. Store-listing assets are NOT a current priority. |
| AdMob account | **Not created.** Agents build the client-side ad stub + SSV edge function against fake/tokens-to-be-faked now; dev creates the account later when prompted. Never commit real IDs — env/config only. |
| Models/flags | `FREE_ONLY` stays (dev chose $0). Backup free models probed 2026-10-07 (`fledge-alpha-free`, `mimo-v2.6-flash-free`, `nemotron-3.5-lightning-free` all survive unattended `--auto`) but are NOT wired in until their no-AI-training status is verified (dev's hard rule). |

## 3. Economy decisions (the dev's answers + what they imply)

### 3.1 Holo variant odds — PROVISIONAL
- Start: none 85% / silver 8% / rainbow 4% / gold 2% / prism 0.8% / galaxy 0.2% (unchanged from
  AGENTS.md).
- Status: **provisional.** The Coordinator watches real pull data later and proposes changes
  before public launch. They must still be published in-game from day one (Play rule).
- Implication for agents: implement as data (a config table/row), not hardcoded constants, so
  tuning is a one-row change. Do not add a second copy of these numbers in client code — the
  client displays what the server publishes.

### 3.2 Pity — CHANGING to soft ramp (needs a migration task)
- Current: hard guarantees via `since_epic` / `since_legendary` counters (`pity` table,
  `pull()` sets `pity_hit`).
- Decision: **replace hard guarantees with a soft ramp** — odds per pull increase with pulls
  since last hit of that rarity tier, so guarantees feel earned but pulls never "dead-hit" at the
  same predictability. (Dev chose this over the implemented hard rule.)
- Open numbers (coordinator proposes in the task, dev approves): ramp start, ramp step, cap.
  Constraint from AGENTS.md that still holds: **pity is per user, global across banners, and
  never resets on hit except the relevant counter.** Publish the ramp on the pull screen in
  plain language (e.g. "epic odds rise every pull since your last epic").
- Migration must keep `pull_log` semantics and stay single-transaction (anti-exploit checklist).

### 3.3 Shop prices — DRAFT SHEET FOR APPROVAL
- Coordinator drafts a complete price sheet; dev approves before any of it is coded live:
  - Monthly Pass: upfront gems + daily gems × 30 days; must beat gem packs on gems-per-dollar by
    a clear margin (AGENTS.md hard rule).
  - Gem packs: 3–4 tiers, first purchase of each tier doubled, no other "bonus" math.
  - Ad-Free Pass: one-time price; same rewards, no extra power.
  - Rewarded ads: amounts deliberately **deferred until the dev sees how fast 1600 alpha gems
    burn in their own play** (explicitly chosen over fixing 40 gems × 4/day now). AGENTS.md
    constraints that already hold: max 4 ads/day, rewarded only, no prompts in first session.
- The sheet lives in this folder (`pipeline/`), is versioned, and nothing ships to `active` until
  the dev replies "approved" in chat.

### 3.4 Wonder Trade locks — COORDINATOR PROPOSES DEFAULTS
- Fixed: account age ≥ 7 days (already in the function). To propose with reasoning:
  - level gate value (server has level/streak data; proposal must say which stat and why),
  - daily cap per account,
  - trade cooldown for cards bought with real money (days; measured from purchase, not pull),
  - reversibility window (AGENTS.md requires admin-reversible swaps).
- House pool (decided): **circulating duplicate exchange + house floor** — the pool is seeded
  from duplicates real players deposit, plus a small reserved house floor per rarity so the pool
  never runs dry or becomes self-dealing. Proposal must state the per-rarity floor sizes and how
  the floor is refilled.

### 3.5 Streak freeze/repair — HYBRID (dev's own words, verbatim intent)
- **Buyable with gems, capped** AND an **ad-only repair option** both exist.
- Balance is explicitly open: the dev wants repairs "not too often… keep it balanced and make the
  ad and reset matter." Implication: repair must never be cheaper/easier than the streak is worth,
  and streak resets should still sting. Coordinator proposes in the price sheet:
  - gem price + max held (2 suggested in interview context, not agreed),
  - ad-repair: which ads (the daily ad slot? separate?), how many misses it can repair (suggest 1),
  - any cooldown between repairs.

## 4. Phase 2 (battles) — DESIGN DOC ONLY
- Dev chose: **draft document only.** No code, no schema fields on `cards` (AGENTS.md rule
  stands until the doc is approved AND Phase 1 is done).
- Deliverable: a `docs/` battle design doc presenting 2–3 mechanic options with tradeoffs
  (deck-of-collected-cards auto-battler vs. hand-played lanes vs. rock-paper-scissors stat duel —
  suggestions, not decisions), each mapped to what it would need from existing tables
  (`user_cards`, rarity, variants) and what new data it would demand later.
- Written by the card lane as a docs-only task after the current queue drains; dev reacts to it
  whenever.

## 5. Art + content gaps
- Set briefs: A-003 owns the 7 set shot lists. Per-set card counts are fixed (8; Con Weekend 16)
  and launch = all 7 sets (§2). Nothing more decided here; the dev judges via sheets + phone.
- Names: agents draft character name lists (adult, no real names —
  franchise/fictional names allowed, same rules as AGENTS.md content rules) once sets are
  approved, for dev approval before the public build.
- Approval flow stays as AGENTS.md: inbox → dev moves to `approved/` + sets `approved: true` →
  importer (dev pastes SQL). The 62 KaT alpha cards are still unimported (dev-only DB step).

## 6. Explicitly deferred / not decided (do NOT let agents guess)
- All real-money prices and ad amounts (until price sheet approved; ad amounts until play data).
- Battle mechanics (doc-only until approved + Phase 1 done).
- Launch date, store listing, Play account steps.
- Whether backup free models are allowed (needs the no-AI-training check the dev must bless).
- Any change to holo odds from live data (proposal-only until launch data exists).

## 7. Batched builder questions — ANSWERED by the dev 2026-10-07 (evening)
From M-001 (motion, sound kit) attempt 1 report — the dev answered via card form:
1. Sound board: **add the debug-only top-bar shortcut** (same pattern as the holo bench).
2. `client/tools/make_bus_layout.gd`: **keep** (layout stays regenerable).
3. Explicit `VARIANT_COUNTS` table in `sfx.gd`: **approved** (implicit in approving the pattern).
These decisions bind M-001 attempt 2+ and any later motion work. The Coordinator folds them into
a BUILDER NOTE on M-001 if the current attempt fails again.

## 8. One agreed AGENTS.md edit (needs dev's own commit or explicit OK)
- Soften "Design in Figma FIRST; code only what the dev has approved there" to: during prototype
  phase, DESIGNER.md + `tokens.tres` are the design standard; Figma-first resumes when the dev
  populates the Figma file. The Coordinator will propose the exact wording as a diff for the dev
  to accept — the Coordinator does not edit AGENTS.md unilaterally.

## 9. Immediate task-file queue derived from this spec (Coordinator to write, in lane order)
1. card: soft-pity ramp migration + published odds/ramp copy (replaces hard `pity_hit` guarantees).
2. card: make holo odds + set sizes + pity parameters server-published config the client reads
   (client already displays server values — verify no duplicated constants).
3. card: wonder-trade locks + circulating house pool per §3.4 (single transaction, escrow, log).
4. motion: unblock as queued (M-001 in flight); fold §7 answers into BUILDER NOTEs once dev answers.
5. design: continue D-queue; batch look-polish for phone sessions per §2.
6. card (later, after queue drains): battle design doc per §4 (`docs/`, docs-only).
7. card: rewarded-ad stub + SSV edge function with fake token verification behind a feature flag
   (real AdMob IDs later, env-only).
8. Coordinator: price sheet draft (§3.3) — a pipeline file, not a lane task.
