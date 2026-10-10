# Visual Redesign Handoff — Premium Mobile TCG (2026-10-10)

Takeover session: elevated the existing D-001 design system into a full premium
card-presentation pass. All work is **uncommitted** in the working tree (per owner
instruction: no commits without authorization). 15 files changed, +923/-181, plus
one new test file.

## What was done

### 1. Card redesign (`client/scripts/card/card_view.gd`, +448/-lines net)

The card is now a collectible object, not a bordered image:

- **Rounded art window** (radius scales with card width) with the whole card
  clipped to the silhouette — art can never bleed past the frame.
- **Name plate**: bottom plate over a subtle scrim; title in display size, set/subtitle
  in caption. Gated off when the plate would be < ~26 px tall so micro cards never
  render unreadable text.
- **Rarity treatments driven by tokens** (`frame_common/rare/epic/legendary` in
  `token_set.gd`): common = brightened gunmetal with hairline border; rare = silver
  bevel + cool specular; epic = violet-enamel band + etched inner line; legendary =
  warm gold embossed frame + corner ornaments + **full-art mode** (band shrinks to a
  hairline, plate floats over art, star field).
- **Rarity gem** chip at top-center for silhouette recognition at grid size.
- Fixed the anchor-normalization bug where `PRESET_FULL_RECT` set before `add_child`
  left the scene's 400x600 offsets — cards rendered oversized and overlapped in the
  collection grid and detail view. Guard normalizes offsets in `_ready`; explicit
  caller-set sizes (pack summary cells) are preserved.

### 2. Holographic system (`client/shaders/holo/*.gdshader`, `card/*`)

All five foil shaders (rainbow, prism, silver, gold, galaxy) plus the parallax and
light shaders were reworked:

- **Rounded-corner window mask** (`window_mask()`, kept in sync across all shaders) so
  foil never spills past the card silhouette.
- **Foil grain**: fine rect-scaled diffraction grain so the foil reads as physical
  laminate, not a flat gradient. Grain and star cells shift with `tilt` for
  angle-dependent movement.
- **Specular sweep** (`card_light.gdshader`): a restrained moving sheen that catches
  the frame and highlights.
- **`motion` uniform**: 0 freezes drift/twinkle for reduced-motion; verified by
  pixel-diff (two frames at motion=0 are byte-identical, MAD 0.0000; foil at motion=1
  reacts to tilt, MAD 12.14).
- **Galaxy**: nebula fbm + parallax star field, stars now fine *round glints* on a
  rect-scaled 9 px grid (were chunky squares at detail size).
- Foil intensity stays under the information layer: text remains readable, original
  art visible beneath (checked in captures).

### 3. Screens

- **Collection tab**: comfortable margins, filter chips (All/Common/Rare/Epic/
  Legendary), ownership badges (x3 / NEW), rarity-tinted frames as the scan cue,
  press feedback on tiles, fixed anchors.
- **Card detail**: enlarged card centered with entrance motion; info panel below with
  name, rarity marker, set/id, owned/seen counts; foil emphasized here (tilt input
  active); 48 dp close target; drag-to-dismiss hint.
- **App shell**: quiet tab bar — one active tab (weight + accent), others recessed;
  previously every tab looked like a filled primary button.
- **Pack opening**: summary grid cells feed real GameState data (rarity, variant,
  pity) into the new card presentation; reveal beat colors the glow/rays from the
  actual pulled rarity; anchor fix so summary cards size correctly.

### 4. Design system additions (`token_set.gd`)

`frame_common` (brightened gunmetal), `frame_rare`, `frame_epic`, `frame_legendary`,
plate/scrim colors, ornament and gem accents, radius steps for the art window — all
consumed through `Tokens.color()/radius()/space()`. No component hardcodes colors or
font sizes (guarded by `test_tokens.gd`).

## Verification

- **Unit tests: 164 passed, 0 failed** (was 152; +12 new in `test_card_frame.gd`
  covering anchor normalization, size preservation, token-driven frame materials,
  plate gating).
- **GPU screenshots** of app_shell, collection_tab, card_detail, pack_opening,
  card_tiers, holo_test render clean (no shader errors) at 540x960.
- **Pixel audits**: grid geometry exact (2:3 cards, 16 px margins, 10 px gaps, rounded
  corners); foil reactivity and reduced-motion freeze proven by frame diffs; text
  contrast on all surfaces verified by `test_tokens.gd` (4.5:1 body).
- Real approved art (`shared/art/approved`, kat-closet) verified in the collection
  and detail layouts via a temporary harness (since removed); art mapping untouched.

## Not changed (deliberately)

- Image pipeline, DB schema, migrations, Supabase behavior, T-010 importer worktree.
- Home/shop/board tabs — the design system is ready to extend there next.
- `AGENTS.md`, `pipeline/PLAYBOOK.md`, `pipeline/FREEBUFF_PROMPT.md` modifications in
  the tree predate this session and were left untouched.

## Known gaps / next step

1. **Real art in runtime collection**: the collection uses whatever `card_art.gd`
   resolves; placeholder silhouettes appear when a card's art files are absent. Natural
   next task (fits queue item D-004-polish-pass): wire the approved kat-closet art
   into the dev collection data so browsing shows real illustrations.
2. Extend tokens to the home tab and shop (once enabled) for full-shell consistency.
3. On-device check: reduced-motion and 60 fps pacing verified headless/GPU-capture only;
   a real Android export pass remains the final gate.

Maps to design queue as an extended polish pass; queue still lists D-004-polish-pass.
