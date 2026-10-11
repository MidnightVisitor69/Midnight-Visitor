# Price sheet — DRAFT for dev approval (2026-10-07)

Coordinator draft per `agent-gaps-spec.md` §3.3. **Nothing here is coded live until the dev
replies "approved" (or edits numbers) in chat.** Currency on screen: Gems, one currency only.
Fairness rules from AGENTS.md apply to every row: no fake discounts, no "bonus" math tricks,
first purchase of each tier doubled is the ONLY multiplier, Monthly Pass must be the best value
by a clear margin, nothing sellable is pay-only.

## 0. Anchor: what a pull costs
- Single pull: **100 gems**
- 10-pull: **900 gems** (one free, no other multiplier — this is a volume discount, not a "bonus")
- Rationale: round number, makes every other row easy to sanity-check in "pulls".

## 1. Gem packs (IAP)
| Pack | Price | Gems | First-buy doubled | Effective gems/$ |
|---|---|---|---|---|
| Pocketful | $0.99 | 80 | 160 | 81–162 |
| Wallet | $4.99 | 500 | 1000 | 100–200 |
| Safe | $9.99 | 1100 | 2200 | 110–220 |
| Vault | $19.99 | 2400 | 4800 | 120–240 |
Notes: first-buy double applies once per tier, forever, tracked per tier server-side. Rounding is
deliberate: bigger pack = slightly better rate, no fake "limited +10%!" timers ever.

## 2. Monthly Pass — $4.99 / 30 days
- Upfront: **300 gems** on purchase.
- Daily: **120 gems** on first sign-in each day, 30 days (missed days are NOT banked — keeps the
  habit loop honest; streak freeze does not protect pass gems).
- Total: 300 + 30×120 = **3900 gems ≈ 39 pulls ⇒ ~$0.13 per pull**.
- Value check vs packs: $4.99 Wallet gives 500–1000 gems; the Pass gives 3900 for the same $4.99
  ⇒ **4–8× better**, satisfying "best value in the shop by a clear margin".
- AGENTS.md guard: target well under $1 per pull — met with 7.7× headroom.

## 3. Ad-Free Pass — $2.99, one time
- Claims the daily ad reward (and streak-repair-by-ad, §5) **without watching ads**, forever.
- Same rewards, no extra power, no exclusives (AGENTS.md: "no extra power").
- Does NOT remove the pass/pack offers or any content — it is pure convenience.
- The "max 4 ads/day" cap applies to watching; the Ad-Free Pass claims the same 4 slots' rewards.

## 4. Rewarded ads — amounts PENDING (dev decision after play data)
- Structure locked by AGENTS.md + spec §2/§3.3: rewarded only, max 4/day, no prompts in first
  session, amounts published before purchasable.
- Placeholder to be filled after the dev sees how fast the 1600 alpha gems burn:
  - `gems_small` (per ad): proposal **40 gems** (pending play data)
  - 4th-slot bonus: none (no pressure mechanics).
- Streak repair via ad: see §5.

## 5. Streak freeze / repair (hybrid, per dev's own words)
Two ways to repair ONE missed day; both capped so "the ad and reset matter":
| Mechanic | Rule | Proposal |
|---|---|---|
| Gem repair | Buy in shop, max **2 held** | **60 gems** each |
| Ad repair | Watch the daily ad, repairs exactly **1 miss**, max **1/month** | free |
- A repair is consumed automatically at day rollover if you missed yesterday; it restores the
  streak as if the day was played (streak counter continues, daily claim becomes available).
- Deliberate friction: monthly cap on ad repair + held-stock cap on gem repair means long streaks
  still require actually showing up. No repair protects Monthly Pass daily gems (§2).
- All repair events logged; repair never grants gems.

## 6. Cosmetics (later, listed for completeness)
Sleeves/frames/backgrounds: gem-priced, no stats, price at the time they ship. Not in this sheet's
scope.

## Approval checklist for the dev
- [ ] Anchor pull prices (100 / 900)
- [ ] Gem pack tiers + first-buy double
- [ ] Monthly Pass math ($4.99, 300 upfront, 120/day)
- [ ] Ad-Free Pass $2.99 and what it covers
- [ ] Streak repair rules (60 gems, hold 2; ad 1 miss/month)
- [ ] I create AdMob + Play billing when you say this sheet is final
Reply "approved" or edit any number in chat — the Coordinator updates this file and turns it into
implementation tasks (prices live server-side in `app_config`/shop tables, never hardcoded in the
client).
