# AGENTS.md — Waifu Card Collector (Card Game Pipeline)

You are the **card game pipeline**. You build and maintain the game app and its backend.
A separate **image pipeline** produces character art. The two pipelines meet at ONE folder
(`shared/`) and never touch each other's code. Read "Handoff Contract" before doing anything with art.

## Current status (read first)
- Supabase project `waifu-card-game`, ref `uombscvrcpjrlbypwcuk` (free tier). DONE and tested:
  schema + RLS, signup trigger (1600 welcome gems), `pull()`, `claim_daily()`, `wonder_trade()`,
  global pity, 6 placeholder cards (set `test`) + `standard` banner. Do not rewrite these; extend.
- Figma file "Neon After-Hours — UI System": https://www.figma.com/design/xFScx1fCfS3sfN5wDfADHI
  (empty). UI concept chosen: **Neon after-hours** — late-night city lounge, deep navy base,
  neon signage accents, rain-glass textures. Energetic but clean; effects stay on cards.
- Launch plan: rewarded ads only. Build the shop (Monthly Pass, gem packs, Ad-Free Pass) but keep it
  hidden behind a feature flag until the dev says to enable it.
- Dev wants to stay anonymous: never put a real name in code, credits, metadata, or commits.
- Godot client: not started.

## Next tasks, in order
1. Create the Godot 4 project in `client/`, Android export preset, Supabase connection (auth + RPC).
2. Holo test card scene: one placeholder card with depth parallax, tilt light, and all holo variant
   shaders, switchable in a debug menu. Dev reviews on a real phone before anything else.
3. Design tokens (colors, fonts, spacing) in Figma AND `client/theme/tokens.tres`, matching.

## Goal
Mobile card game for Google Play in the spirit of Pokémon TCG Live: collect, open packs, build
decks, battle. Signature feature: animated, shaded, holographic waifu cards. Fun first, cheap to
run, modest ad income. Original characters, original mechanics and names (no Pokémon terms, card
frames, or trade dress). Suggestive (Nikke-level fanservice) but Play-safe.

## Stack
- Client: Godot 4 (GDScript), Android export
- Backend: Supabase (Auth, Postgres, Storage, Edge Functions) — stay on the free tier until real traction
- Ads: Google AdMob, rewarded ads ONLY, with server-side verification (SSV)
- Store: Google Play, rating target Teen or Mature 17+

## Repo layout
```
client/                 Godot 4 project (UI, card display, animations)
supabase/migrations/    SQL schema + Postgres functions (all game logic lives here)
supabase/functions/     Edge functions (AdMob SSV callback, Play Integrity check)
shared/                 HANDOFF ZONE — see contract below
docs/                   design notes
```

## Bandwidth rule (keeps hosting free)
Card art ships INSIDE the app (Play Asset Delivery packs for new sets), never downloaded from
Supabase Storage at runtime. Supabase serves game data only. Free tier egress is small; art would
burn through it.

## Golden rule: server decides everything
The client only displays and requests. Pulls, rewards, streaks, currency, trades, and card
ownership are decided by Postgres functions running in a single transaction. Never trust
any value the client sends except "which action" and an idempotency key.

## Handoff Contract (image pipeline <-> card pipeline)
Image pipeline OWNS: `shared/art/inbox/`
Card pipeline OWNS: everything else in the repo
Human (the dev) OWNS: moving files from inbox to approved

1. Image pipeline drops a folder per card into `shared/art/inbox/<card_id>/`:
   - `base.png` (portrait, 2:3, min 1024x1536) — ALL rarities
   - `depth.png` (grayscale depth map, same size) — rare and up
   - `char.png` + `bg.png` (character cut out on transparency, background alone) — epic and up
   - `card.json` matching `shared/card_manifest.schema.json`
2. The dev reviews and moves approved pairs to `shared/art/approved/` and sets `"approved": true`.
3. Card pipeline ONLY reads `shared/art/approved/`. It never generates, edits, or deletes art.
4. Card pipeline imports approved cards: uploads PNG to Supabase Storage, inserts a row in
   `cards`, then writes `"imported": true` back into the JSON. Re-running the import must be
   safe (skip anything already imported).
5. Image pipeline never touches `client/`, `supabase/`, or the database.

(In steps 2-4, "pair"/"JSON" means the card's folder and its `card.json`.)

### Manifest fields (`card.json`)
```json
{
  "card_id": "string, lowercase-kebab, unique, never reused",
  "character_name": "string",
  "rarity": "common | rare | epic | legendary",
  "set": "string, e.g. launch-01",
  "tags": ["string"],
  "approved": false,
  "imported": false,
  "gen": { "model": "string", "seed": 0, "prompt_id": "string" }
}
```

## Card visuals (client, all done with Godot shaders — no hand animation)
Rarity decides the art TIER. Every effect is a shader driven by the device tilt (gyroscope)
or touch-drag, so one piece of art gets all effects for free.
- Common: static `base.png`
- Rare: depth-map parallax (card looks 3D when tilted) + subtle idle "breathing" warp
- Epic: rare effects + separate char/bg layers + dynamic light that follows tilt
- Legendary: epic effects + full-art frameless layout + particle accents

## Holo variants (rolled at pull time, independent of rarity)
A holo is a foil shader over the card, so variants cost zero extra art.
- Stored on `user_cards.variant`, NOT on `cards`. Same card, different variant = different collectible.
- Odds (tune later, publish in-game): none 85%, silver 8%, rainbow 4%, gold 2%, prism 0.8%, galaxy 0.2%
- Holo only available on rare and up. Each variant = one shader + one color ramp texture.
- Variant is rolled server-side inside `pull()`, same transaction, logged in `pull_log`.

## UI rules
- 4 tabs only: Home (daily claim + open packs), Collection, Trade, Shop. No other menus at launch.
- ONE currency on screen: Gems. Never add a second currency without the dev's approval.
  Duplicates are not converted into anything; they are wonder-trade fodder.
- Max one notification dot per tab. No launch popups, no "limited offer" interrupts, no countdown spam.
- The pack opening and card detail views are the showpiece; every other screen stays quiet and simple.
- Pity counter and drop odds always visible on the pull screen (Google Play requires odds before purchase).
- Settings shows lifetime money spent (`profiles.total_spent_cents`).

## UI quality bar (no AI slop, no clutter)
- During the prototype phase, DESIGNER.md + `client/theme/tokens.tres` are the design
  standard; code from those. Figma-first resumes when the dev populates the Figma file —
  from then on, design in Figma FIRST and code only what the dev has approved there.
  Never invent screens in code.
- Use the design tokens file (`client/theme/tokens.tres`) for every color, font size, spacing,
  radius, and animation duration. Hardcoded values are bugs.
- Two fonts max: one display font for titles/card names, one UI font for everything else.
- Every screen answers one question. If a screen needs a tutorial popup, the screen is wrong.
- Motion has a job: confirm a tap, show where something went, or build anticipation (pack opening).
  No idle wobble, glow, or particles on menus. Effects belong to the cards.
- Banned: rainbow gradients on UI, glow on everything, inconsistent icon styles, stock-looking
  AI backgrounds, text on busy art without a scrim, more than one CTA competing per screen.
- Thumb-first: primary actions in the bottom third, minimum 48dp tap targets.

## Monetization rules (fair by design)
- Rewarded ads only. No banners, no interstitials, ever. Max 4 ads/day, each for a clearly stated reward
  (e.g. 40 gems, or a streak repair). No ad prompts during a player's first session.
- Monthly Pass (the main product): small upfront gems + daily gems for 30 days. Must be the best value
  in the shop by a clear margin. Target well under $1 per pull.
- Gem packs: simple tiers, first purchase of each tier doubled. No "bonus" math tricks.
- Ad-Free Pass (one-time): claims daily ad rewards without watching. Same rewards, no extra power.
- Cosmetics: card sleeves, frames, collection backgrounds. Purely visual.
- NEVER: cards only obtainable with money, pity that resets, odds hidden, pressure popups, fake discounts.
- Pity carries across all banners (already implemented: `pity` is per user, not per banner).

## Content rules (both pipelines, Google Play)
- Every character clearly an adult in face, body, and stated age. Reject anything ambiguous.
- No nudity, no sexual acts, no see-through explicit detail. Swimsuits/outfits/poses: OK.
- No existing franchise characters, no copied art from other games.

## Build order (do not skip ahead)

### Phase 1 — Collection (current focus)
1. Schema: `profiles`, `cards`, `user_cards`, `currency_ledger`, `pull_log`, `streaks`, `banners`
2. `pull(banner_id, idempotency_key)` function with pity counter, published odds
3. Daily login + streak (with streak freeze item)
4. Godot client: login, pull screen, collection screen, card detail
5. Card shaders: parallax, idle, tilt light, holo variants (build a test scene with one card first)
6. Pack-opening animation (the dopamine moment — rarity reveal, holo flash)
7. Rewarded ads + SSV edge function (reward granted ONLY by SSV callback)
8. Wonder Trade (see below)

Phase 1 is done when a player can log in, keep a streak, open packs, see animated/holo cards,
browse their collection, watch a rewarded ad, and wonder-trade — with no exploits found in testing.

### Phase 2 — PvE battles (do NOT start until the dev says Phase 1 is done)
Battle design is not decided yet. Do not add battle stats or fields to `cards` until it is.

### Later — only after launch and only if the dev approves
Ranked PvP, posted trading.

## Wonder Trade (v1 trading)
- Player deposits one card into the pool for its rarity; gets a random card of the same rarity back.
- Pool is seeded with house cards so it never runs dry.
- Locks: account age >= 7 days AND level gate; daily cap per account.
- Card is escrowed (removed from inventory) in the same transaction as the swap.
- Cards bought with real money are tradeable only after a cooldown.
- Every transfer logged in `trade_log`; any swap reversible by admin.

## Anti-exploit checklist (apply to every function)
- Single transaction, `SELECT ... FOR UPDATE` on rows being changed
- Idempotency key on every write action
- Rate limit per user per action
- Row Level Security on every table; clients cannot write game tables directly
- Play Integrity token checked before trades and purchases

## Style
- Keep files small; one feature per migration
- Comment WHY, not what
- Write a SQL test for every game function before marking it done
