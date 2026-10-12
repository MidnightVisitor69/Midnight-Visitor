extends "res://tests/test_case.gd"
## M-003: PagerMath pure physics functions.
##
## Tests cover:
##   - target_index: slow short drag -> stays; fast flick -> next/prev; at last card -> clamped
##   - snap_progress: ease-out with BACK overshoot
##   - rubber_band_offset: resistance curve, max stretch clamp
##   - card_transform: centered, neighbors peek at 8%, scaled 0.92, dimmed
##   - stagger_delay: diagonal wave pattern
##   - can_play_slide_sound: 90ms rate limit
##
## Fault-injection guards: remove end clamp -> last-card test FAILS; remove rate limit -> its test FAILS.

const PagerMathScript := preload("res://scripts/motion/pager_math.gd")

const CARD_WIDTH := 300.0
const COUNT := 5


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng


# --- target_index ---------------------------------------------------------------

func test_target_index_no_flick_stays_on_current() -> void:
	# Slow drag, low velocity, offset near center -> stays
	var idx := PagerMathScript.target_index(2, 2.0 * CARD_WIDTH + 10.0, 100.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 2, "slow drag near center stays")


func test_target_index_no_flick_snaps_to_nearest() -> void:
	# No decisive velocity, but offset past halfway -> snaps to next
	var idx := PagerMathScript.target_index(2, 2.0 * CARD_WIDTH + CARD_WIDTH * 0.6, 100.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 3, "offset past halfway snaps next")
	
	# Offset before halfway -> snaps to previous
	idx = PagerMathScript.target_index(2, 2.0 * CARD_WIDTH - CARD_WIDTH * 0.6, 100.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 1, "offset before halfway snaps prev")


func test_target_index_fast_flick_right_moves_prev() -> void:
	# Dragging right (positive velocity) -> previous card (index - 1)
	var idx := PagerMathScript.target_index(2, 2.0 * CARD_WIDTH, 800.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 1, "fast flick right (positive vel) moves to prev")


func test_target_index_fast_flick_left_moves_next() -> void:
	# Dragging left (negative velocity) -> next card (index + 1)
	var idx := PagerMathScript.target_index(2, 2.0 * CARD_WIDTH, -800.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 3, "fast flick left (negative vel) moves to next")


func test_target_index_velocity_threshold_is_max_of_600_or_35pct() -> void:
	# At 300px card width, 35% = 105px, so threshold is 600
	var idx := PagerMathScript.target_index(2, 2.0 * 300.0, 500.0, COUNT, 300.0)
	assert_eq(idx, 2, "500 px/s below 600 threshold -> no flick")
	
	idx = PagerMathScript.target_index(2, 2.0 * 300.0, 700.0, COUNT, 300.0)
	assert_eq(idx, 1, "700 px/s above 600 threshold -> flick")
	
	# At 2000px card width, 35% = 700px, so threshold is 700
	idx = PagerMathScript.target_index(2, 2.0 * 2000.0, 650.0, COUNT, 2000.0)
	assert_eq(idx, 2, "650 px/s below 700 (35%) threshold -> no flick")
	
	idx = PagerMathScript.target_index(2, 2.0 * 2000.0, 800.0, COUNT, 2000.0)
	assert_eq(idx, 1, "800 px/s above 700 (35%) threshold -> flick")


func test_target_index_at_first_card_clamped() -> void:
	# At index 0, flick right (positive vel) should stay at 0
	var idx := PagerMathScript.target_index(0, 0.0, 1000.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 0, "at first card, flick right clamps to 0")
	
	# Offset negative with flick should still clamp
	idx = PagerMathScript.target_index(0, -50.0, 1000.0, COUNT, CARD_WIDTH)
	assert_eq(idx, 0, "at first card, negative offset clamps to 0")


func test_target_index_at_last_card_clamped() -> void:
	# At last index, flick left (negative vel) should stay at last
	var idx := PagerMathScript.target_index(COUNT - 1, (COUNT - 1) * CARD_WIDTH, -1000.0, COUNT, CARD_WIDTH)
	assert_eq(idx, COUNT - 1, "at last card, flick left clamps to last")
	
	# Offset past end with flick should still clamp
	idx = PagerMathScript.target_index(COUNT - 1, COUNT * CARD_WIDTH, -1000.0, COUNT, CARD_WIDTH)
	assert_eq(idx, COUNT - 1, "at last card, offset past end clamps to last")


func test_target_index_single_card_always_zero() -> void:
	var idx := PagerMathScript.target_index(0, 0.0, 1000.0, 1, CARD_WIDTH)
	assert_eq(idx, 0, "single card always index 0")


# --- snap_progress --------------------------------------------------------------

func test_snap_progress_ease_out_with_overshoot() -> void:
	# At p=0, progress=0
	assert_almost(PagerMathScript.snap_progress(0.0), 0.0, 0.001)
	# At p=1, progress=1
	assert_almost(PagerMathScript.snap_progress(1.0), 1.0, 0.001)
	# Mid-point should be > 0.5 (ease-out)
	var mid := PagerMathScript.snap_progress(0.5)
	assert_true(mid > 0.5, "ease-out: progress at 0.5 > 0.5, got %f" % mid)
	# Overshoot: at some p < 1, progress > 1
	var has_overshoot := false
	for i in range(1, 100):
		var p := i / 100.0
		if PagerMathScript.snap_progress(p) > 1.0:
			has_overshoot = true
			break
	assert_true(has_overshoot, "BACK curve must overshoot past 1.0")


# --- rubber_band_offset ---------------------------------------------------------

func test_rubber_band_zero_at_zero() -> void:
	assert_almost(PagerMathScript.rubber_band_offset(0.0, CARD_WIDTH), 0.0, 0.001)


func test_rubber_band_resistance_curve() -> void:
	# Small overshoot -> less than linear
	var small := PagerMathScript.rubber_band_offset(50.0, CARD_WIDTH)
	assert_true(small < 50.0, "small overshoot resisted: %f < 50" % small)
	assert_true(small > 0.0, "but still moves: %f > 0" % small)
	
	# Larger overshoot -> diminishing returns
	var large := PagerMathScript.rubber_band_offset(200.0, CARD_WIDTH)
	assert_true(large < 200.0, "large overshoot resisted: %f < 200" % large)
	# Ratio should decrease
	assert_true(large / 200.0 < small / 50.0, "resistance increases with overshoot")


func test_rubber_band_max_stretch_clamped() -> void:
	var max_stretch := CARD_WIDTH * PagerMathScript.MAX_RUBBER_BAND_FRACTION
	var huge := PagerMathScript.rubber_band_offset(10000.0, CARD_WIDTH)
	assert_almost(huge, max_stretch, 1.0, "max stretch clamped to %f, got %f" % [max_stretch, huge])
	
	# Negative overshoot also clamped
	var huge_neg := PagerMathScript.rubber_band_offset(-10000.0, CARD_WIDTH)
	assert_almost(huge_neg, -max_stretch, 1.0, "negative max stretch clamped")


func test_rubber_band_sign_preserved() -> void:
	assert_true(PagerMathScript.rubber_band_offset(100.0, CARD_WIDTH) > 0.0)
	assert_true(PagerMathScript.rubber_band_offset(-100.0, CARD_WIDTH) < 0.0)


# --- card_transform -------------------------------------------------------------

func test_card_transform_centered() -> void:
	var t := PagerMathScript.card_transform(0, 0.5, CARD_WIDTH)
	assert_almost(t.x, 0.0, 0.001)
	assert_almost(t.scale, 1.0, 0.001)
	assert_almost(t.modulate_alpha, 1.0, 0.001)
	assert_eq(t.z_index, 100)


func test_card_transform_left_neighbor() -> void:
	# At progress 0 (fully left), neighbor peeks 8% from left edge
	var t := PagerMathScript.card_transform(-1, 0.0, CARD_WIDTH)
	var peek := CARD_WIDTH * PagerMathScript.NEIGHBOR_PEEK_FRACTION
	assert_almost(t.x, -CARD_WIDTH + peek, 0.001)
	assert_almost(t.scale, PagerMathScript.NEIGHBOR_SCALE, 0.001)
	assert_almost(t.modulate_alpha, PagerMathScript.NEIGHBOR_ALPHA, 0.001)
	assert_eq(t.z_index, 50)
	
	# At progress 1 (becoming center), neighbor at center
	t = PagerMathScript.card_transform(-1, 1.0, CARD_WIDTH)
	assert_almost(t.x, 0.0, 0.001)
	assert_almost(t.scale, 1.0, 0.001)
	assert_almost(t.modulate_alpha, 1.0, 0.001)


func test_card_transform_right_neighbor() -> void:
	# At progress 0 (fully right), neighbor peeks 8% from right edge
	var t := PagerMathScript.card_transform(1, 0.0, CARD_WIDTH)
	var peek := CARD_WIDTH * PagerMathScript.NEIGHBOR_PEEK_FRACTION
	assert_almost(t.x, CARD_WIDTH - peek, 0.001)
	assert_almost(t.scale, PagerMathScript.NEIGHBOR_SCALE, 0.001)
	assert_almost(t.modulate_alpha, PagerMathScript.NEIGHBOR_ALPHA, 0.001)
	assert_eq(t.z_index, 50)
	
	# At progress 1 (becoming center), neighbor at center
	t = PagerMathScript.card_transform(1, 1.0, CARD_WIDTH)
	assert_almost(t.x, 0.0, 0.001)
	assert_almost(t.scale, 1.0, 0.001)
	assert_almost(t.modulate_alpha, 1.0, 0.001)


# --- stagger_delay --------------------------------------------------------------

func test_stagger_delay_diagonal_wave() -> void:
	# 3 columns: indices 0,1,2 (row 0), 3,4,5 (row 1), etc.
	# Wave front = row + col
	assert_almost(PagerMathScript.stagger_delay(0, 3), 0.0, 0.001)      # row 0, col 0
	assert_almost(PagerMathScript.stagger_delay(1, 3), 0.03, 0.001)     # row 0, col 1
	assert_almost(PagerMathScript.stagger_delay(2, 3), 0.06, 0.001)     # row 0, col 2
	assert_almost(PagerMathScript.stagger_delay(3, 3), 0.03, 0.001)     # row 1, col 0
	assert_almost(PagerMathScript.stagger_delay(4, 3), 0.06, 0.001)     # row 1, col 1
	assert_almost(PagerMathScript.stagger_delay(5, 3), 0.09, 0.001)     # row 1, col 2


# --- can_play_slide_sound -------------------------------------------------------

func test_slide_sound_rate_limit_allows_after_90ms() -> void:
	assert_true(PagerMathScript.can_play_slide_sound(0, 100), "first play always allowed")
	assert_true(PagerMathScript.can_play_slide_sound(100, 200), "100ms gap allowed")
	assert_true(not PagerMathScript.can_play_slide_sound(100, 150), "50ms gap blocked")
	assert_true(not PagerMathScript.can_play_slide_sound(100, 189), "89ms gap blocked")
	assert_true(PagerMathScript.can_play_slide_sound(100, 190), "90ms gap allowed")


# --- fault-injection guards -----------------------------------------------------

## Guard: remove the end clamp in target_index -> last-card test FAILS
func test_guard_target_index_end_clamp() -> void:
	# This test passes because the clamp exists. If you remove the clampi()
	# in target_index, the last-card test above would return COUNT (out of bounds).
	var idx := PagerMathScript.target_index(COUNT - 1, COUNT * CARD_WIDTH, -1000.0, COUNT, CARD_WIDTH)
	assert_true(idx < COUNT, "index must be clamped to valid range: %d < %d" % [idx, COUNT])


## Guard: remove the rate limit check -> rate limit test FAILS
func test_guard_slide_sound_rate_limit() -> void:
	# This test passes because can_play_slide_sound enforces 90ms.
	# If you remove the check, the 50ms gap test would incorrectly return true.
	assert_true(not PagerMathScript.can_play_slide_sound(100, 150), "50ms gap must be blocked")