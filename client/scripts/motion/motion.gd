class_name Motion
extends RefCounted
## Every duration and curve the game animates with, in one file (ANIMATOR.md:
## the dev tunes here; these move into the design tokens later).
##
## Nothing here draws. Screens read these constants so changing a timing is one
## edit instead of a hunt, and so a screenshot can seek to a fixed progress
## point and land on the same frame every time.
##
## Bands the dev set: tap feedback 80-120 ms, card flip 250-350 ms, pack tear
## 400-700 ms, and a build-up that may run to 1.4 s for legendary only. No
## linear UI motion anywhere; the helpers below name the four curves in use.

# --- tap feedback ---------------------------------------------------------------
const TAP_MS := 100.0
## A pressed control dips to this scale and springs back.
const TAP_PRESS_SCALE := 0.94

# --- the pack ------------------------------------------------------------------
## Degrees the pack leans toward a finger before the rip. Small on purpose: it
## has to read as "it noticed you", not as a wobble (AGENTS.md: no idle motion).
const PACK_LEAN_DEG := 6.0
const PACK_LEAN_DAMP := 12.0
const PACK_LEAN_OFFSET_PX := 6.0
const PACK_SHAKE_AMPLITUDE_PX := 7.0
## The nervous wobble before the rip. Five cycles across the shake.
const PACK_SHAKE_CYCLES := 5.0
const PACK_SHAKE_MS := 180.0
## 520 ms sits mid-band: long enough to follow the finger, short enough that a
## 10-pull does not feel like waiting.
const PACK_TEAR_MS := 520.0
## The torn strip falls, tips and fades over this long.
const PACK_STRIP_MS := 420.0
const PACK_STRIP_TIP_DEG := 14.0
## How far the strip drops, as a fraction of pack height.
const PACK_STRIP_FALL_FRACTION := 0.55
## How much of the pack height the rip removes.
const PACK_STRIP_FRACTION := 0.28
const PACK_BURST_MS := 260.0
## An untouched pack tears itself after this long, so the moment is reachable
## one-handed and by anyone who cannot swipe.
const PACK_AUTO_TEAR_SECONDS := 0.6
## Horizontal drag that counts as a full rip.
const PACK_RIP_PX := 260.0

# --- cards ---------------------------------------------------------------------
const CARD_OUT_MS := 300.0
const CARD_SLIDE_MS := 260.0
const CARD_FLIP_MS := 300.0
## How far a card travels out of the pack, as a fraction of card height.
const CARD_TRAVEL_FRACTION := 0.10
const CARD_REST_SCALE := 0.90
const HOLO_FLASH_MS := 150.0
const HOLO_FLASH_ALPHA := 0.85
## Epic and legendary ramp a glow in the tease colour before the flip.
const GLOW_RAMP_MS := 260.0
const GLOW_SCALE := 1.22
const GLOW_ALPHA := 0.85

# --- legendary build -----------------------------------------------------------
const DIM_MS := 320.0
const DIM_ALPHA := 0.74
const RAYS_MS := 900.0

# --- hold on the reveal, per rarity --------------------------------------------
## Only legendary reaches 1.4 s; everything below it must stay snappy or a
## 10-pull turns into a queue.
const HOLD_COMMON := 0.25
const HOLD_RARE := 0.5
const HOLD_EPIC := 0.9
const HOLD_LEGENDARY := 1.4

# --- summary -------------------------------------------------------------------
const SUMMARY_MS := 320.0
const SUMMARY_GRID_COLUMNS := 5

# --- curves --------------------------------------------------------------------
## Arrivals overshoot a little, then settle.
const ARRIVE := Tween.TRANS_QUART
const ARRIVE_EASE := Tween.EASE_OUT
## Exits accelerate away.
const EXIT := Tween.TRANS_CUBIC
const EXIT_EASE := Tween.EASE_IN
## One pop, for the pack lifting and the card leaving the foil.
const POP := Tween.TRANS_BACK
const POP_EASE := Tween.EASE_OUT
## The flip itself is symmetric, so either ease works; ease-out reads calmer.
const FLIP := Tween.TRANS_SINE
const FLIP_EASE := Tween.EASE_IN_OUT


## How long the reveal holds a card of this rarity, in seconds. An unknown
## rarity is treated as common: short and forgettable beats the alternative.
static func hold_seconds(rarity: String) -> float:
	match rarity:
		"rare":
			return HOLD_RARE
		"epic":
			return HOLD_EPIC
		"legendary":
			return HOLD_LEGENDARY
		_:
			return HOLD_COMMON


## scale.x for a card flip at progress p in [0, 1]: 1 -> 0 at the halfway point
## (where the face swaps) -> 1. Pure, so a screenshot can seek to any frame.
static func flip_scale(p: float) -> float:
	return absf(cos(PI * clampf(p, 0.0, 1.0)))


## Shake offset in pixels at progress p in [0, 1]. Deterministic from p alone
## (no clock), so the same progress always draws the same frame.
static func shake_offset(p: float, amplitude: float = PACK_SHAKE_AMPLITUDE_PX) -> float:
	var t := clampf(p, 0.0, 1.0)
	return sin(t * TAU * PACK_SHAKE_CYCLES) * t * amplitude