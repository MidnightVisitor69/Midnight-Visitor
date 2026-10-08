extends "res://tests/test_case.gd"
## M-001: the sound kit's plumbing.
##
## Covers the four rules that keep the mix pleasant rather than the .wav files
## themselves (pipeline/check_audio.py is the independent guard for those):
## variant choice, +/-3% pitch jitter, the 3-voice cap, and the global toggle.
##
## The helpers under test take an injected RNG and an explicit variant table so
## a test can pin them; nothing here depends on an audio device being present,
## which is what keeps these runnable headless.
##
## Fault-injection guards are marked "Guard:"; each fails when its guard is gone:
##   - the random draw in variant_for
##   - the clamp on PITCH_JITTER
##   - MAX_VOICES == 3
##   - the enabled check in play()
##   - the oldest-voice eviction in _take_voice()

const SfxScript := preload("res://scripts/audio/sfx.gd")
const BoardScript := preload("res://scripts/dev/sound_board.gd")

const VOICE_TOLERANCE := 0.0001


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	return rng


## How many AudioStreamPlayers the pool actually holds, counted as children so
## the test sees the real nodes and not just the bookkeeping array.
func _live_voices(sfx: Node) -> int:
	sfx.voice_pool_size()
	return sfx.get_child_count()


# --- variants ---------------------------------------------------------------

func test_variants_cycle_through_every_declared_count() -> void:
	var rng := _rng()
	var seen := {}
	for i in 200:
		seen[SfxScript.variant_for("card_slide", rng)] = true
	for n in 3:
		assert_true(seen.has("card_slide_%d" % (n + 1)),
			"card_slide variant %d is reachable" % (n + 1))


func test_sound_without_variants_keeps_its_own_name() -> void:
	# pack_tear is a single crafted moment; there is nothing to vary.
	assert_eq(SfxScript.variant_for("pack_tear", _rng()), "pack_tear")


## Guard: the random draw. A version that returned a fixed stem would still
## return a plausible name, so assert the set of results is not a single value.
func test_variant_choice_is_actually_random() -> void:
	var rng := _rng()
	var first := SfxScript.variant_for("tap", rng)
	var differs := false
	for i in 50:
		if SfxScript.variant_for("tap", rng) != first:
			differs = true
			break
	assert_true(differs, "50 taps must not all sound identical")


func test_every_variant_the_kit_declares_exists_on_disk() -> void:
	# A typo in VARIANT_COUNTS would be a silent dead button, not a crash.
	for name in SfxScript.VARIANT_COUNTS:
		for n in range(1, int(SfxScript.VARIANT_COUNTS[name]) + 1):
			var path := "res://audio/%s_%d.wav" % [name, n]
			assert_true(ResourceLoader.exists(path), "missing sound file " + path)


func test_sounds_offered_by_the_board_all_resolve_to_a_real_file() -> void:
	var board: BoardScript = BoardScript.new()
	for name in board.sounds_offered():
		var stem := SfxScript.variant_for(name, _rng())
		assert_true(ResourceLoader.exists("res://audio/%s.wav" % stem),
			"sound board offers '%s' with no wav" % name)
	board.free()


# --- pitch jitter ------------------------------------------------------------

## Guard: the clamp on PITCH_JITTER. Set the constant to 0.10 and the samples
## leave the +/-3% window and this fails.
func test_pitch_jitter_stays_within_three_percent() -> void:
	var rng := _rng()
	for i in 500:
		var pitch := SfxScript.pitch_jitter_for(rng)
		assert_true(pitch >= 1.0 - SfxScript.PITCH_JITTER - VOICE_TOLERANCE
				and pitch <= 1.0 + SfxScript.PITCH_JITTER + VOICE_TOLERANCE,
			"pitch %f outside the +/-3%% window" % pitch)


func test_pitch_jitter_actually_varies_around_unity() -> void:
	# A jitter of exactly 1.0 would pass the window test but sound like a robot.
	var rng := _rng()
	var lo := 2.0
	var hi := 0.0
	for i in 200:
		var p := SfxScript.pitch_jitter_for(rng)
		lo = minf(lo, p)
		hi = maxf(hi, p)
	assert_true(lo < 0.999, "jitter never dips below 1.0")
	assert_true(hi > 1.001, "jitter never rises above 1.0")


# --- voice cap --------------------------------------------------------------

## Guard: MAX_VOICES. Raise it to 6 and this fails.
func test_voice_pool_is_capped_at_three() -> void:
	assert_eq(SfxScript.MAX_VOICES, 3, "never more than three overlapping sounds")


func test_pool_holds_exactly_three_players() -> void:
	var sfx: Node = SfxScript.new()
	tree.root.add_child(sfx)
	assert_eq(_live_voices(sfx), 3, "one recycled player per allowed voice")
	sfx.queue_free()


## Guard: the eviction in _take_voice. Without it a rapid burst would keep
## adding players and the pool would grow past the cap.
func test_burst_of_sounds_never_grows_the_pool() -> void:
	var sfx: Node = SfxScript.new()
	tree.root.add_child(sfx)
	for i in 25:
		sfx.play("tap")
	assert_eq(_live_voices(sfx), 3, "a 25-tap burst must still own 3 players")
	sfx.queue_free()


func test_a_full_pool_still_hands_out_a_playing_voice() -> void:
	# Dropping the oldest must leave someone audible, not return null.
	var sfx: Node = SfxScript.new()
	tree.root.add_child(sfx)
	for i in 6:
		var p: AudioStreamPlayer = sfx.play("tap")
		assert_true(p != null, "play(%d) returned no voice" % i)
		assert_eq(p.bus, "SFX", "everything routes through the SFX bus")
	sfx.queue_free()


# --- the toggle -------------------------------------------------------------

## Guard: the enabled check in play(). Remove it and sound keeps playing after
## the player turned it off, which is the one thing they asked not to happen.
func test_disabled_plays_nothing() -> void:
	var sfx: Node = SfxScript.new()
	tree.root.add_child(sfx)
	sfx.set_enabled(false)
	assert_eq(sfx.play("tap"), null, "a muted sfx must stay silent")
	assert_eq(sfx.play_and_haptic("pack_tear"), null, "no sound while muted")
	sfx.queue_free()


func test_disabled_also_silences_haptics() -> void:
	var sfx: Node = SfxScript.new()
	tree.root.add_child(sfx)
	sfx.set_enabled(false)
	assert_eq(sfx.haptic("pack_tear"), 0, "haptics follow the sound toggle")
	assert_eq(sfx.haptic("reveal_legendary"), 0, "same toggle, same silence")
	sfx.queue_free()


func test_enabled_by_default() -> void:
	# AGENTS.md: the launch build is not silent unless the player says so.
	var sfx: Node = SfxScript.new()
	tree.root.add_child(sfx)
	assert_eq(sfx.get("enabled"), true, "sound defaults to on")
	sfx.queue_free()


func test_only_the_two_rare_moments_have_a_haptic() -> void:
	# "Short and rare" (ANIMATOR.md): no buzzing on taps or card swipes.
	assert_eq(SfxScript.HAPTIC_MS.get("pack_tear", 0), 20)
	assert_eq(SfxScript.HAPTIC_MS.get("reveal_legendary", 0), 35)
	assert_eq(SfxScript.HAPTIC_MS.get("tap", 0), 0, "no haptic on a tap")
	assert_eq(SfxScript.HAPTIC_MS.get("card_slide", 0), 0, "no haptic on a swipe")


# --- the board --------------------------------------------------------------

func test_board_offers_a_button_per_sound() -> void:
	var board: BoardScript = BoardScript.new()
	var buttons := board.sound_buttons()
	for name in board.sounds_offered():
		assert_true(buttons.any(func(b: Button) -> bool: return b.text.find(name) == 0),
			"no button to audition '%s'" % name)
	board.free()


func test_board_buttons_are_tap_sized() -> void:
	var board: BoardScript = BoardScript.new()
	for b in board.sound_buttons():
		assert_true(b.custom_minimum_size.y >= 48.0, "48dp tap target on " + b.name)
	board.free()


func test_board_exposes_one_screenshot_state() -> void:
	var board: BoardScript = BoardScript.new()
	assert_eq(board.screenshot_count(), 1)
	assert_eq(board.screenshot_setup(0), "sound_board")
	board.free()