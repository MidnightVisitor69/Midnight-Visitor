class_name PagerMath
extends RefCounted
## Pure physics for the horizontal card pager and the collection scroller.
## No Godot nodes, no time, no randomness - only math. Every function is
## deterministic so a test (or a screenshot seeking to a fixed progress) lands
## on the same frame every run.

## Velocity threshold (px/s) that counts as a "flick" to the next/prev card.
const FLICK_VELOCITY_PX_S := 600.0
## Or 35% of card width - whichever is easier to reach on the current screen.
const FLICK_FRACTION := 0.35
## Snap duration (ms) with a tiny BACK overshoot so the card settles with weight.
const SNAP_MS := 260.0
## Neighbor peek at the edges as a fraction of card width.
const NEIGHBOR_PEEK_FRACTION := 0.08
## Neighbor scale when peeking.
const NEIGHBOR_SCALE := 0.92
## Neighbor modulate alpha when peeking.
const NEIGHBOR_ALPHA := 0.7
## Rubber-band resistance: how much extra drag is needed per pixel past the end.
const RUBBER_BAND_FACTOR := 0.35
## Maximum rubber-band stretch as a fraction of card width.
const MAX_RUBBER_BAND_FRACTION := 0.25
## Collection tile stagger delay (ms) for the first-screen pop-in.
const STAGGER_MS := 30.0
## Sound rate limit: minimum ms between card_slide plays.
const SLIDE_SOUND_MIN_INTERVAL_MS := 90.0


## Target index from current offset and velocity.
##   index: current centered index (0-based)
##   offset: horizontal scroll offset in pixels (0 = first card centered)
##   velocity: current drag velocity in px/s (positive = dragging right -> previous card)
##   count: total number of cards
##   card_width: width of one card in pixels
## Returns the index the pager should snap to.
static func target_index(index: int, offset: float, velocity: float, count: int, card_width: float) -> int:
	if count <= 1:
		return 0
	var threshold := maxf(FLICK_VELOCITY_PX_S, card_width * FLICK_FRACTION)
	var target := index
	# Dragging right (positive velocity) moves to previous card (index - 1)
	# Dragging left (negative velocity) moves to next card (index + 1)
	if velocity > threshold:
		target = index - 1
	elif velocity < -threshold:
		target = index + 1
	else:
		# No decisive flick: snap to nearest based on offset
		var center_offset := offset - index * card_width
		if center_offset > card_width * 0.5:
			target = index + 1
		elif center_offset < -card_width * 0.5:
			target = index - 1
	return clampi(target, 0, count - 1)


## Snap progress curve: ease-out with a tiny BACK overshoot.
## p in [0, 1] -> eased progress in [0, 1] (may briefly exceed 1.0 during overshoot).
static func snap_progress(p: float) -> float:
	var t := clampf(p, 0.0, 1.0)
	# TRANS_BACK with ease-out: overshoots slightly past 1.0 then settles
	# Standard BACK ease-out: 1 + (t-1)^2 * ((c+1)*(t-1) + c) where c = 1.70158
	var c := 1.70158
	return 1.0 + (t - 1.0) * (t - 1.0) * ((c + 1.0) * (t - 1.0) + c)


## Rubber-band offset for dragging past the first/last card.
##   overshoot: how many pixels past the edge (positive = past right edge, negative = past left)
##   card_width: width of one card
## Returns the visual offset to apply (always less than overshoot, with resistance).
static func rubber_band_offset(overshoot: float, card_width: float) -> float:
	var max_stretch: float = card_width * MAX_RUBBER_BAND_FRACTION
	var abs_over: float = absf(overshoot)
	if abs_over <= 0.0:
		return 0.0
	# Resistance curve: asymptotic approach to max_stretch, strong resistance at small overshoot
	var k: float = card_width * RUBBER_BAND_FACTOR
	var stretched: float = sign(overshoot) * max_stretch * (1.0 - 1.0 / (1.0 + abs_over / k))
	return stretched


## Card transform for a given index relative to the centered card.
##   rel_index: index - center_index (0 = centered, -1 = left neighbor, 1 = right neighbor)
##   progress: snap progress in [0, 1] (from snap_progress)
##   card_width: width of one card
## Returns {x: float, scale: float, modulate_alpha: float, z_index: int}
static func card_transform(rel_index: int, progress: float, card_width: float) -> Dictionary:
	var peek := card_width * NEIGHBOR_PEEK_FRACTION
	match rel_index:
		0:
			# Centered card: moves from its start position to center
			return {
				"x": -progress * card_width * rel_index,  # always 0 for rel_index 0
				"scale": 1.0,
				"modulate_alpha": 1.0,
				"z_index": 100
			}
		-1:
			# Left neighbor (previous card): peeks from left, scales up as it becomes center
			var x := -card_width + peek + progress * (card_width - peek)
			var scale := lerpf(NEIGHBOR_SCALE, 1.0, progress)
			var alpha := lerpf(NEIGHBOR_ALPHA, 1.0, progress)
			return {"x": x, "scale": scale, "modulate_alpha": alpha, "z_index": 50}
		1:
			# Right neighbor (next card): peeks from right, scales up as it becomes center
			var x := card_width - peek - progress * (card_width - peek)
			var scale := lerpf(NEIGHBOR_SCALE, 1.0, progress)
			var alpha := lerpf(NEIGHBOR_ALPHA, 1.0, progress)
			return {"x": x, "scale": scale, "modulate_alpha": alpha, "z_index": 50}
		_:
			# Farther cards: hidden (handled by caller culling)
			return {"x": rel_index * card_width, "scale": NEIGHBOR_SCALE, "modulate_alpha": NEIGHBOR_ALPHA, "z_index": 0}


## Staggered entrance delay for collection tiles (first screen only).
##   index: tile index in the visible grid (0-based, row-major)
##   columns: number of grid columns
## Returns delay in seconds.
static func stagger_delay(index: int, columns: int) -> float:
	var row := index / columns
	var col := index % columns
	# Diagonal wave: row + col determines wave front
	var wave := row + col
	return (wave * STAGGER_MS) / 1000.0


## Whether a slide sound should play based on rate limiting.
##   last_play_time: timestamp (ms) of the last card_slide play, 0 if never
##   now: current timestamp (ms)
## Returns true if enough time has passed.
static func can_play_slide_sound(last_play_time: int, now: int) -> bool:
	return (now - last_play_time) >= SLIDE_SOUND_MIN_INTERVAL_MS