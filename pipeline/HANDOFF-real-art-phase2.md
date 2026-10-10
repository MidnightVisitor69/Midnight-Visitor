# Phase 2 Handoff — Real Approved Art in the Runtime Collection (2026-10-10)

Follows `HANDOFF-visual-redesign.md`. That pass left one documented gap: the
runtime collection showed placeholder silhouettes because no screen ever resolved
the approved artwork. This pass closes that gap. Everything is **uncommitted** in
the working tree (no commits/pushes/merges, per owner instruction).

## The problem, traced

Three independent breaks kept real art from rendering:

1. **Runtime staging dir was incomplete.** The client loads art via
   `CardArt` → `res://art/<set>/<card_id>/base.png`. `client/art/` (gitignored,
   shipped via build) held only 12 of the 62 approved cards.
2. **No screen asked for real art.** The offline/preview fixture `demo_rows()`
   (and card_detail's two demo fixtures) hardcoded fictional cards with
   `art_path="placeholder/<rarity>.png"`, so they always fell back to the
   procedural placeholder.
3. **Contract mismatch for production.** The T-010 importer writes
   `cards.art_path = "shared/art/approved/<card_id>/base.png"` to the DB. That
   path is outside the Godot project, so the client's `res://` resolver could not
   load it even in a live Supabase session.

## Inventory (source of truth: `shared/art/approved/*/card.json`)

- **62 approved cards**, every one valid: `card_id` == folder name,
  `approved:true`, rarity ∈ {common, rare, epic, legendary}, `base.png` is a
  well-formed 1024×1536 PNG (exact 2:3 card ratio). **0 missing, 0 invalid.**
- Sets: `kat-closet` (32), `kat-daily` (30). Rarities: common 32, rare 18,
  epic 6, legendary 6.
- **All art is base-only** (no depth/char/bg layers exist). `CardView`'s tier
  resolver therefore renders every card at the common tier (base art, no
  parallax) while keeping its rarity frame and foil — the correct graceful
  degradation; nothing is fabricated to fill the missing layers.
- `imported:false` on all 62 — the T-010 importer has not run against Supabase.

## What was built

### 1. `tools/sync-approved-art.mjs` (new)

One reproducible tool that reads the approved manifests and:
- **Emits the catalog** `client/scripts/card/card_catalog.gd`.
- **Stages art** — copies each `base.png` → `client/art/<set>/<card_id>/base.png`
  (byte-identical copies are skipped on re-run).
- **Validates strictly** — a manifest that is not approved, whose `card_id`
  disagrees with its folder, has an unknown rarity, or a missing/wrong-size
  `base.png` is reported and skipped (never silently mapped). Exits non-zero on
  any failure so CI can gate.

Run it whenever new art is approved: `node tools/sync-approved-art.mjs`
(`--dry-run` / `--no-stage` supported).

### 2. `client/scripts/card/card_catalog.gd` (new, generated)

A **compiled const** index `card_id -> {name, rarity, set_id, art_path}`, copied
verbatim from the manifests. It is a `.gd`, not a runtime `.json`, because the
Android export preset has an empty `include_filter` — GDScript and imported PNGs
under `res://` are packaged, loose non-resource files are not. Metadata stays
separate from presentation; `art_path` is relative to `res://art/`.

### 3. `client/scripts/card/card_art.gd` (resolver)

`textures_for()` now resolves each card by trying, in order:
1. the **server-provided `art_path`** (a live server path always wins), then
2. the **catalog entry** for that `card_id` — which turns the DB's
   `shared/art/approved/...` form *and* any empty path into a loadable
   `res://art/` location.

The resolution is memoized per `(card_id, art_path)`. The deliberate
`placeholder/<rarity>.png` scheme is still honored as-is (never overridden), and
an unknown card or absent file still falls back to the procedural placeholder —
every existing `test_card_art.gd` contract is preserved.

### 4. Fixtures rewired to real cards

- `collection_tab.demo_rows()` now builds rows from `CardCatalog` (real ids,
  names, rarities, sets, art_paths) with deterministic copy counts and holo
  variants so grouping/badges still have work to do. `screenshot_setup` set
  sizes updated to the real sets.
- `card_detail.demo_group()` / `demo_legendary()` point at real cards
  (`kat-daily-1735-day` rare, `kat-daily-2344-sleep` legendary).

## Verification actually run

- **Unit tests: 175 passed, 0 failed** (was 164; +11 in the new
  `client/tests/test_art_catalog.gd` — catalog self-consistency, id round-trip,
  set sorting, resolver catalog/DB-form fallback, placeholder preservation, memo
  reset). The new tests assert resolution *behavior*, so they stay green both in
  CI (no art staged) and on a dev box (art staged).
- **GPU screenshots** (off-screen window, not `--headless`): `collection_tab`
  and `card_detail` render the real illustrations — verified by eye and by a
  pixel audit: **9/9 sampled tiles have unique color signatures** (each card a
  distinct illustration), **0 placeholder-like near-grey tiles**, and grid
  geometry exact (162×243 cards = 2:3, 16px margins, 10px gaps). Detail view
  shows the legendary with full-art gold frame + galaxy foil over real art.

## Packaging / Android note

`client/art/` is gitignored (alpha art never enters git). The staged PNGs are a
**build-time artifact**: on any fresh checkout, run
`node tools/sync-approved-art.mjs` *then* `godot --headless --path client --import`
so the editor imports `res://art/**.png` as resources and includes them in the
PCK. The catalog `.gd` ships automatically as code. No machine-specific absolute
paths are used — all loads go through `res://`.

**Import state was verified, not assumed.** Before the import pass, the staged
PNGs had no `.godot/imported/` entries and no `.import` sidecars, so the GPU
screenshots were only rendering via the desktop raw-file fallback
(`Image.load_from_file` + `FileAccess`), which does **not** work on Android
(files live inside the PCK). After `--import`, all 62 cards resolve through
`ResourceLoader` as `CompressedTexture2D` (0 raw-only, 0 missing) — the
Android-viable path. `CardArt._read_texture` already prefers `ResourceLoader`,
so device builds load the imported resources.

**Exact missing prerequisite for a real APK build in this environment:** the
Android SDK is installed (`C:\Users\vanna\Android\Sdk`, with build-tools /
platforms / platform-tools) and JDK-17 is on PATH, and Godot export templates
4.7.2.stable are present — but Godot's editor settings have no Android SDK path
configured (`export/android/android_sdk_path` is empty), so a command-line
`--export-release Android` would fail at the SDK-lookup step. Configuring that
one setting (and providing a debug keystore) is the only thing standing between
this tree and a real APK. No device/emulator test was performed.

## Not touched (deliberately)

- T-010 importer, Studio roster, Supabase schema/migrations/production data,
  image-generation pipeline, wardrobe scheduler.
- Pre-existing uncommitted edits (`AGENTS.md`, `pipeline/PLAYBOOK.md`,
  `pipeline/FREEBUFF_PROMPT.md`, and the other `pipeline/*.md`) — preserved as-is.
- The prior visual-redesign diff (shaders, `card_view.gd`, `token_set.gd`) —
  intact.

## Known gaps / next step

1. **Supabase rows don't exist yet.** All 62 cards are `imported:false`, so a
   live session has no `user_cards` to browse. The offline collection + detail
   are fully wired to real art; the production path will resolve as soon as the
   importer runs (the DB-form `art_path` now resolves via the catalog fallback).
   Running the importer is out of scope here (touches production data).
2. **Layer art.** depth/char/bg don't exist yet; when the pipeline produces them,
   rare+ cards will automatically gain parallax/full-art treatment (the tier
   resolver already keys off layer presence) with no code change.
3. A real Android export/device pass remains the final packaging gate (not
   available in this environment).
