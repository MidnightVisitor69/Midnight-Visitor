# Battle Design Options (Phase 2 — PvE)

**Status:** Draft for dev review. No code, no schema changes.  
**Constraint:** AGENTS.md monetization rules apply — no pay-to-win, no cards locked behind money, pity never resets.

---

## Option A: Auto-Battler "Night Shift"

### Core Loop
Player assembles a **squad of 5 cards** from their collection. Each run = one "shift" (3–5 waves). Waves auto-resolve: the squad attacks in initiative order (speed stat), enemies counter. Player input = **pre-shift squad selection + one mid-shift "tactical call"** (target priority / defensive stance / burst). Run rewards scale with waves cleared.

### Rarity & Holo Factor
- **Rarity** → base stat budget (HP, ATK, SPD, skill slots). Common=3 slots, Rare=4, Epic=5, Legendary=6.
- **Holo variants** → **cosmetic only** (visual flair on skill proc). No stat bonus. *Pay-to-win check: PASS.*
- Duplicate cards → **merge into "limit break"** (+1 skill slot, max +3). Merge uses dupes, not currency.

### Server-Authoritative Model
- `POST /rpc/start_shift(squad_card_ids[], seed)` → server generates enemy wave data, returns `shift_id` + deterministic wave plan.
- `POST /rpc/resolve_shift(shift_id, tactical_call_enum)` → single transaction: simulates all waves, writes `shift_log`, awards currency/xp, updates `user_cards` limit-break progress. Idempotency key on both calls.
- Enemy stats drawn from `enemy_templates` (config table), scaled by player's highest squad rarity.

### New Data Needed (described, not created)
| Table / Field | Purpose |
|---|---|
| `enemy_templates(id, name, base_hp, base_atk, base_spd, skills_json, rarity_tier)` | Config; one row per enemy archetype. |
| `shifts(id, user_id, squad_json, seed, wave_plan_json, state, started_at, finished_at)` | One row per run. `state`: `active` \| `resolved` \| `forfeited`. |
| `shift_log(id, shift_id, wave, events_json)` | Replay/debug; append-only. |
| `user_cards.limit_break` (int, default 0) | Tracks duplicate merges. |
| `card_skills(card_id, slot_index, skill_id, unlock_lb)` | Skill per slot; `unlock_lb` = limit-break tier needed. |

### Client Complexity & Risks
- **Low–Medium.** Squad builder UI, wave log replay, tactical call buttons. Auto-sim is server-side; client only animates the returned log.
- **Risk:** "Auto" feels passive. Mitigation: tight 15–20s waves, juicy VFX on skill procs (holo flash), tactical call every 2 waves.
- **Risk:** Stat inflation. Mitigation: enemy scaling references squad's *median* rarity, not max.

---

## Option B: Lane Defense "Neon Perimeter"

### Core Loop
3 vertical lanes. Player places **up to 3 cards per lane** (front/mid/back) from hand of 5 drawn from their squad of 12. Each turn: draw 1, place 1, lanes resolve simultaneously (front → back). Enemies spawn at lane tops, march down. Goal: survive N turns or kill boss. Runs are short (2–3 min).

### Rarity & Holo Factor
- **Rarity** → **deck cost** (Common=1, Rare=2, Epic=3, Legendary=4). Squad cost cap = 12 (tunable). Forces trade-offs.
- **Holo variants** → **lane aura** (passive buff to adjacent cards in same lane): Silver=+5% ATK, Rainbow=+5% SPD, Gold=+5% HP, Prism=cleanse debuff on turn start, Galaxy=copy neighbor's keyword. *Pay-to-win check: PASS — small, positional, not raw power.*
- Duplicates → **fuse for +1 cost efficiency** (same card costs −1, min 1). Soft cap per card.

### Server-Authoritative Model
- `POST /rpc/start_run(squad_card_ids[], seed)` → returns `run_id`, initial hand, enemy spawn schedule (deterministic from seed).
- `POST /rpc/play_turn(run_id, placements[], draw_choice)` → single transaction: validates placements vs hand/cost, resolves lane combat, draws next card, writes `turn_log`, checks win/loss. Idempotency key per turn.
- Enemy schedule from `enemy_waves(run_tier, wave, lane, enemy_template_id, mods_json)`.

### New Data Needed
| Table / Field | Purpose |
|---|---|
| `enemy_templates` (same as Option A) | Shared config. |
| `runs(id, user_id, squad_json, seed, hand_json, turn, state, started_at)` | Active run state. |
| `turn_log(id, run_id, turn, placements_json, resolution_json)` | Replay/debug. |
| `user_cards.fuse_level` (int, default 0) | Tracks cost-reduction fuses. |
| `card_keywords(card_id, keyword_id)` | Keywords for holo auras (e.g. `shield`, `pierce`, `haste`). |

### Client Complexity & Risks
- **Medium.** Lane grid, drag-to-place, hand management, simultaneous resolution animation. More UI surface than Option A.
- **Risk:** APM pressure on mobile. Mitigation: generous turn timer (30s), auto-place "best fit" button.
- **Risk:** Holo auras create "must-have" variants. Mitigation: auras are *lane-local* and *small*; a non-holo Epic beats a holo Rare on raw stats.

---

## Option C: Rock-Paper-Scissors Stat Duel "Signal Clash"

### Core Loop
1v1 duels. Each card has **three stats**: **Power / Tech / Charm** (P/T/C). Each turn, both sides **secretly pick a stat**; reveal → P beats T, T beats C, C beats P. Winner deals damage = their stat value × multiplier. First to 0 HP loses. Player brings **3 cards** (active + 2 reserves); can swap once per duel (cooldown 3 turns). Best-of-3 duels per run.

### Rarity & Holo Factor
- **Rarity** → **stat budget** (Common=180 total, Rare=210, Epic=240, Legendary=270) distributed across P/T/C. Higher rarity = more *specialization* (spikier stats), not just higher totals.
- **Holo variants** → **stat jitter** (±5% on reveal, once per duel). Silver=+5% to chosen stat, Rainbow=−5% to opponent's chosen stat, Gold=reveal opponent's pick *after* you lock (info advantage), Prism=reroll your own pick once, Galaxy=copy opponent's stat value for that turn. *Pay-to-win check: PASS — jitter is variance, not power creep; info advantages are skill-expressive.*
- Duplicates → **stat reallocation** (move 5 points between P/T/C, max 3 times per card).

### Server-Authoritative Model
- `POST /rpc/start_duel(attacker_card_id, defender_card_ids[], seed)` → returns `duel_id`, both cards' full stat blocks (server knows both; client sees only own).
- `POST /rpc/lock_stat(duel_id, turn, stat_enum, idempotency_key)` → client commits hashed pick (commit-reveal). Server stores hash.
- `POST /rpc/reveal_stat(duel_id, turn, stat_enum, idempotency_key)` → server verifies hash, resolves, writes `duel_log`, returns damage + next state. Single transaction per reveal.
- Best-of-3 tracked in `duels` row; run ends when one side wins 2.

### New Data Needed
| Table / Field | Purpose |
|---|---|
| `card_stats(card_id, power, tech, charm)` | Base stats per card (derived from rarity budget + design). |
| `duels(id, user_id, attacker_card_id, defender_card_ids[], seed, state, turn, wins_attacker, wins_defender)` | Duel state machine. |
| `duel_log(id, duel_id, turn, attacker_pick, defender_pick, resolution_json)` | Replay/debug; commit-reveal audit. |
| `user_cards.stat_realloc` (jsonb: `{power:0, tech:0, charm:0}`) | Tracks reallocation points spent. |

### Client Complexity & Risks
- **Low.** Minimal UI: 3 stat buttons, commit/reveal flow, swap reserve button. High readability.
- **Risk:** RPS feels random. Mitigation: commit-reveal + holo info variants + reserve swap = mind game depth.
- **Risk:** Stat memorization. Mitigation: server sends *only* own stats; opponent stats hidden until reveal. Player learns matchups over time.

---

## Recommendation

**Option B (Lane Defense)** — best fit for the project:

1. **Collection-first:** Uses the *whole* collection (squad of 12, hand of 5). Players see more of their cards per session.
2. **Holo feels good, not mandatory:** Lane auras are visible, tactile, and *positional* — you place the holo card to buff neighbors. Pure visual+light mechanical payoff.
3. **Mobile-native:** Turn-based, portrait, thumb-friendly drag. 2–3 min sessions fit "after-hours" vibe.
4. **Server-simple:** Deterministic spawn schedule + per-turn validation = easy to audit, hard to exploit.
5. **Extensible:** Boss waves, event modifiers, co-op (shared lanes) later without rewriting core.

**Option C** is a strong #2 if the dev wants lighter client scope and deeper mind games.  
**Option A** is the safest "ship fast" path but risks feeling like a background task.

---

## Open Questions for the Dev

1. **Session length target:** 2 min (Option C), 3 min (Option B), 5 min (Option A)?
2. **Progression hook:** Card XP / limit break (A), fuse cost reduction (B), stat reallocation (C) — which feels best?
3. **Enemy variety:** Hand-authored templates (all options) or procedural from card stats (C only)?
4. **Social layer:** Ghost data (async PvP later) — Option B lanes map cleanly; Option C duels map cleanly; Option A needs work.
5. **Art ask:** Option B needs lane VFX (projectiles, impacts). Option C needs stat-reveal drama. Option A needs skill VFX. Which art budget fits?
6. **Monetization touchpoint:** Ad-rewarded "mercenary slot" (extra lane card for one run)? Must stay cosmetic/power-neutral per AGENTS.md.
7. **Phase 1 gate:** Confirm exploit checklist + Pixel 6 playtest pass before any battle code lands.

---

*End of draft. Dev reacts → Coordinator turns approved option into lane tasks.*