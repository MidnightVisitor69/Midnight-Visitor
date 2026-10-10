class_name PackOpening
extends Control
## The dopamine moment (task M-002): anticipation, rip, reveal, payoff.
##
## Structure, deliberately:
##   - RevealPlan (pure) decides the order, the beats and the state machine.
##   - PendingPack journals the pull so a crash cannot double-charge or lose
##     cards. This screen only reports progress into it.
##   - Motion holds every duration and curve, so the dev tunes in one place.
##   - Sfx supplies every sound and haptic, behind its own toggle.
##
## The visuals are driven by plain properties ("_tear", "_flip", ...) that the
## sequence tweens and _sync_visual() reads. That is also how screenshots work:
## a frame is just a set of property values, seeked directly with no tween and
## no clock, so a captured frame lands on the same pixels every run.
##
## Every animation is skippable by tap (M-002: "stays skippable at every
## moment"), and the whole moment is reachable with one-handed taps: an
## untouched pack rips itself after Motion.PACK_AUTO_TEAR_SECONDS.

const CardViewScene := preload("res://scenes/card/card_view.tscn")
const CardArtScript := preload("res://scripts/card/card_art.gd")
const PendingPackScript := preload("res://scripts/app/pending_pack.gd")
const PlaceholderArtScript := preload("res://scripts/card/placeholder_art.gd")
const PackTearShader := preload("res://shaders/fx/pack_tear.gdshader")
const PackStripShader := preload("res://shaders/fx/pack_strip.gdshader")
const RevealRaysShader := preload("res://shaders/fx/reveal_rays.gdshader")

## Emitted when the player is finished and the shell should take them back Home.
signal closed

## Reveal cue per rarity. Commons get none: a reveal pad on every grey card
## would be noise, not reward.
const REVEAL_SOUNDS := {
	"rare": "reveal_rare",
	"epic": "reveal_epic",
	"legendary": "reveal_legendary",
}
const RARITIES_GLOW := ["epic", "legendary"]
const MIN_TAP_DP := 48.0

const BG_COLOR := Color(0.031, 0.047, 0.118)

# --- state ---------------------------------------------------------------------
## Which beat of the moment we are in. See RevealPlan for the string contract.
var step := RevealPlan.STEP_CLOSED
## Index into the beats; -1 before the first card.
var beat_index := -1

var _cards: Array = []
var _beats: Array[Dictionary] = []
var _owned_keys: Array[String] = []
## Tease colour of the pack as a whole (the best rarity inside), and of the
## card currently on the reveal stage.
var _tease := RevealPlan.TEASE_COLORS["common"]
var _pity_shown := false

# --- animated properties (see _sync_visual) -----------------------------------
var _shake := 0.0
var _tear := 0.0
var _strip := 0.0
var _burst := 0.0
var _card_out := 0.0
var _flip := 0.0
var _glow := 0.0
var _flash := 0.0
var _rays := 0.0
var _dim := 0.0
var _rip_x := 0.5
var _lean := 0.0
var _lean_target := 0.0

# --- internals -----------------------------------------------------------------
var _built := false
var _screenshot_mode := false
var _run := 0
var _tweens := {}
var _ripping := false
var _rip_from := 0.0
var _ripping_touched := false
var _art_cache: Dictionary = {}

var _pack: ColorRect
var _strip_rect: ColorRect
var _backlight: ColorRect
var _dim_layer: ColorRect
var _glow_layer: ColorRect
var _rays_rect: ColorRect
var _flash_rect: ColorRect
var _card_slot: Control
var _card_front: CardView
var _card_back: Panel
var _pity_tag: Label
var _counter: Label
var _skip_button: Button
var _done_button: Button
var _summary_grid: GridContainer
var _summary_root: Control
var _summary_count: Label

var _pack_size := Vector2(300, 440)
var _card_size := Vector2(360, 540)
var _pack_center := Vector2.ZERO
var _card_center := Vector2.ZERO
var _additive := CanvasItemMaterial.new()


func _ready() -> void:
	_ensure_built()
	set_process(true)


# --- setup (and resume) --------------------------------------------------------

## Build the moment from a pull result.
##   cards        the server's cards, still in pull order
##   owned_keys   RevealPlan.owned_key() strings owned BEFORE this pull, for NEW
##   resume       {"step": String, "index": int} from GameState, so a relaunch
##                picks up mid-reveal instead of starting over
func setup(cards: Array, owned_keys: Array, resume: Dictionary) -> void:
	_ensure_built()
	_cancel_tweens()
	_run += 1
	_cards = cards
	_beats = RevealPlan.build(cards)
	_owned_keys.assign(owned_keys)
	_tease = RevealPlan.best_tease_color(cards)
	_pack_rip_mat().set_shader_parameter("inner_light", _tease)
	_layout()
	_clear_summary()
	_enter(str(resume.get("step", RevealPlan.STEP_CLOSED)), int(resume.get("index", -1)))
	if _screenshot_mode:
		return
	_start()


## The pure half of "skip", exposed for tests and for the Skip button.
static func skip_step(from: String) -> String:
	return RevealPlan.skip_to(from)


## Which beat the reveal is on, or -1. Read by tests.
func current_beat() -> int:
	return beat_index


## Whether this screen currently shows the summary.
func is_summary() -> bool:
	return step == RevealPlan.STEP_SUMMARY


## Summary cells, in order. Read by tests to check the NEW badges.
func summary_cells() -> Array[Control]:
	_ensure_built()
	var out: Array[Control] = []
	for child in _summary_grid.get_children():
		out.append(child as Control)
	return out


## The uniform values the tear shader is showing right now. A screenshot seeks
## these; a test reads them to prove the rip actually moved.
func tear_uniforms() -> Dictionary:
	var mat := _pack_rip_mat()
	if mat == null:
		return {}
	return {"tear": mat.get_shader_parameter("tear"), "rip_x": mat.get_shader_parameter("rip_x")}


func tear_progress() -> float:
	return _tear


# --- the sequence --------------------------------------------------------------

## Enter a step and start whatever runs there. Also the resume path: a relaunch
## lands here with a step and an index and picks straight up, silently.
func _enter(new_step: String, index: int) -> void:
	step = new_step
	match new_step:
		RevealPlan.STEP_REVEALING:
			beat_index = clampi(index, -1, _beats.size() - 1)
			if beat_index < _beats.size():
				_prepare_beat()
			else:
				_go_summary()
				return
			_start_reveal()
		RevealPlan.STEP_SUMMARY:
			beat_index = _beats.size()
			_go_summary()
			return
		_:
			beat_index = -1
			_reset_beat()
			_start()
	_sync_visual()


func _start() -> void:
	match step:
		RevealPlan.STEP_CLOSED:
			_run_closed()
		RevealPlan.STEP_TEARING:
			_start_tear()
		RevealPlan.STEP_REVEALING:
			_start_reveal()


## Pack sits still until the player rips it - or until the accessibility timer
## rips it for them. Anticipation is the point; an automatic tear must not feel
## like the game played itself, so it only fires on a screen nobody touched.
func _run_closed() -> void:
	await _wait(Motion.PACK_AUTO_TEAR_SECONDS)
	if step != RevealPlan.STEP_CLOSED:
		return
	_start_tear()


func _start_tear() -> void:
	if step != RevealPlan.STEP_CLOSED:
		return
	_ripping = false
	step = RevealPlan.STEP_TEARING
	var token := _run + 1
	_run = token
	_tween("_shake", 0.0, 1.0, Motion.PACK_SHAKE_MS, Motion.ARRIVE, Motion.ARRIVE_EASE)
	await _wait(Motion.PACK_SHAKE_MS / 1000.0)
	if token != _run:
		return
	# The rip itself: one sound, one haptic, the light of the best rarity inside.
	_play_and_haptic("pack_tear")
	_tween("_tear", 0.0, 1.0, Motion.PACK_TEAR_MS, Motion.EXIT, Motion.EXIT_EASE)
	_tween("_burst", 0.0, 1.0, Motion.PACK_TEAR_MS * 0.5, Motion.ARRIVE, Motion.ARRIVE_EASE)
	await _wait(Motion.PACK_TEAR_MS / 1000.0)
	if token != _run:
		return
	# The strip is off now, so the journal can say the pack is open.
	PendingPackScript.mark_torn()
	_tween("_strip", 0.0, 1.0, Motion.PACK_STRIP_MS, Motion.EXIT, Motion.EXIT_EASE)
	_tween("_burst", 1.0, 0.0, Motion.PACK_STRIP_MS, Motion.EXIT, Motion.EXIT_EASE)
	await _wait(Motion.PACK_STRIP_MS / 1000.0)
	if token != _run:
		return
	_enter(RevealPlan.STEP_REVEALING, 0)


func _start_reveal() -> void:
	_run_reveal()


## One beat at a time, awaiting a timer between phases rather than a tween's
## finished signal: a skipped tween is killed, and a killed tween never finishes,
## so a skip during the flip would strand this loop forever.
func _run_reveal() -> void:
	var token := _run + 1
	_run = token
	while true:
		if token != _run or step != RevealPlan.STEP_REVEALING:
			return
		if beat_index >= _beats.size():
			_go_summary()
			return
		await _play_beat(token)
		if token != _run or step != RevealPlan.STEP_REVEALING:
			return
		beat_index += 1
		PendingPackScript.mark_revealed(beat_index - 1)
		_prepare_beat()


func _play_beat(token: int) -> void:
	var beat := _beats[beat_index]
	var rarity := str(beat["rarity"])
	_play("card_slide")
	await _wait(Motion.CARD_SLIDE_MS / 1000.0)
	if token != _run:
		return
	# Epic and legendary build first: the glow tells you something is behind the
	# card before the flip takes it away.
	if rarity in RARITIES_GLOW:
		_tween("_glow", 0.0, 1.0, Motion.GLOW_RAMP_MS, Motion.ARRIVE, Motion.ARRIVE_EASE)
		if rarity == "legendary":
			_tween("_rays", 0.0, 1.0, Motion.RAYS_MS, Motion.ARRIVE, Motion.ARRIVE_EASE)
			_tween("_dim", 0.0, 1.0, Motion.DIM_MS, Motion.ARRIVE, Motion.ARRIVE_EASE)
		await _wait(Motion.GLOW_RAMP_MS / 1000.0)
		if token != _run:
			return
	var reveal := str(REVEAL_SOUNDS.get(rarity, ""))
	if reveal.is_empty():
		_play("card_flip")
	elif rarity == "legendary":
		# The one moment allowed both channels: the longest beat on screen and a
		# 35 ms haptic (ANIMATOR.md).
		_play("card_flip")
		_play_and_haptic(reveal)
	else:
		_play(reveal)
		_play("card_flip")
	_tween("_flip", 0.0, 1.0, Motion.CARD_FLIP_MS, Motion.FLIP, Motion.FLIP_EASE)
	if bool(beat["flash"]):
		# The flash is what sells the foil; the shimmer rides under it.
		_tween("_flash", Motion.HOLO_FLASH_ALPHA, 0.0, Motion.HOLO_FLASH_MS,
				Motion.EXIT, Motion.EXIT_EASE)
		_play("holo_shimmer")
	await _wait(Motion.CARD_FLIP_MS / 1000.0)
	if token != _run:
		return
	if rarity == "legendary":
		# Let the rays burn out slowly on their own, so the payoff settles.
		_tween("_rays", 1.0, 0.0, Motion.RAYS_MS, Motion.EXIT, Motion.EXIT_EASE)
		_tween("_dim", 1.0, 0.0, Motion.DIM_MS, Motion.EXIT, Motion.EXIT_EASE)
	await _wait(float(beat["hold_seconds"]))


## Skip: from any skippable step, straight to the summary. Kills every tween
## first so nothing lands on top of the summary a frame later.
func _skip() -> void:
	if step == RevealPlan.STEP_SUMMARY:
		return
	_play("tap")
	_go_summary()


func _go_summary() -> void:
	if step == RevealPlan.STEP_SUMMARY:
		return
	_cancel_tweens()
	_run += 1
	step = RevealPlan.STEP_SUMMARY
	beat_index = _beats.size()
	_pending_pack_kept = true
	_build_summary()
	_sync_visual()


## "Done" is the only place the journal is cleared: until then a crash on the
## summary has to be able to bring the same pack back.
func _on_done() -> void:
	_play("acquire")
	PendingPackScript.finish()
	closed.emit()


func _reset_beat() -> void:
	_tease = RevealPlan.best_tease_color(_cards)
	_pity_shown = false
	for p in ["_card_out", "_flip", "_glow", "_flash", "_rays", "_dim"]:
		set(p, 0.0)
	if _pack_rip_mat() != null:
		_pack_rip_mat().set_shader_parameter("inner_light", _tease)
	_glow_layer.modulate = Color(_tease, 0.0)
	if _rays_mat() != null:
		_rays_mat().set_shader_parameter("ray_color", _tease)


func _prepare_beat() -> void:
	if beat_index < 0 or beat_index >= _beats.size():
		_reset_beat()
		return
	var beat := _beats[beat_index]
	_tease = RevealPlan.tease_color(str(beat["rarity"]))
	_pity_shown = bool(beat["pity"])
	_card_front.set_card(str(beat["rarity"]), _art_for(beat), _meta_for(beat))
	_card_front.set_variant(str(beat["variant"]))
	_pity_tag.text = "Pity!"
	for p in ["_card_out", "_flip", "_glow", "_flash", "_rays", "_dim"]:
		set(p, 0.0)
	_glow_layer.modulate = Color(_tease, 0.0)
	if _rays_mat() != null:
		_rays_mat().set_shader_parameter("ray_color", _tease)
	if _counter != null:
		_counter.text = "%d / %d" % [beat_index + 1, _beats.size()]


var _pending_pack_kept := false


# --- input ---------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_began(t.position)
		else:
			_touch_ended(t.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_touch_moved((event as InputEventScreenDrag).position)
		accept_event()
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed:
				_touch_began(m.position)
			else:
				_touch_ended(m.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_touch_moved(mm.position)
			accept_event()


## Touching a sealed pack makes it lean toward the finger and rustle: the pack
## notices you before it opens. A swipe across its top edge is the rip.
func _touch_began(pos: Vector2) -> void:
	match step:
		RevealPlan.STEP_CLOSED:
			if _screenshot_mode:
				return
			_ripping = true
			_rip_from = pos.x
			_ripping_touched = false
			_rip_x = clampf(pos.x / maxf(size.x, 1.0), 0.0, 1.0)
			_lean_target = _lean_from(pos)
			_play("pack_rustle")
		RevealPlan.STEP_TEARING, RevealPlan.STEP_REVEALING:
			# Tap anywhere skips the current beat: the rip finishes, then the
			# card flips now instead of after its glow.
			_skip_current()
		_:
			pass


func _touch_moved(pos: Vector2) -> void:
	if not _ripping or step != RevealPlan.STEP_CLOSED:
		return
	_ripping_touched = true
	_lean_target = _lean_from(pos)
	if absf(pos.x - _rip_from) >= Motion.PACK_RIP_PX:
		_start_tear()


## Released without a long enough swipe: treat it as the accessibility tap.
func _touch_ended(_pos: Vector2) -> void:
	if not _ripping:
		return
	_ripping = false
	_lean_target = 0.0
	if step == RevealPlan.STEP_CLOSED:
		_start_tear()


func _lean_from(pos: Vector2) -> float:
	var half := maxf(_pack_size.x * 0.5, 1.0)
	return clampf((pos.x - _pack_center.x) / half, -1.0, 1.0)


func _skip_current() -> void:
	match step:
		RevealPlan.STEP_TEARING:
			_skip()
		RevealPlan.STEP_REVEALING:
			# Cancel the glow ramp and the flip, then move on.
			_cancel_tweens()
			beat_index += 1
			PendingPackScript.mark_revealed(beat_index - 1)
			_prepare_beat()
			_run += 1
			_start_reveal()
		_:
			pass


func _process(delta: float) -> void:
	# Lean is the only thing eased per frame; everything else is a tween.
	var f := 1.0 - exp(-maxf(Motion.PACK_LEAN_DAMP, 0.0) * maxf(delta, 0.0))
	var next := lerpf(_lean, _lean_target, f)
	if not is_equal_approx(next, _lean):
		_lean = next
		_sync_visual()


# --- sound ---------------------------------------------------------------------
## Everything goes through the Sfx autoload, which owns the global toggle, the
## variant picks and the 3-voice cap (M-001). Looked up lazily so the screen also
## builds in tests and screenshots with no autoloads around.

func _sfx_node() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Sfx")


func _play(name: String) -> void:
	if _screenshot_mode or name.is_empty():
		return
	var s := _sfx_node()
	if s != null and s.has_method("play"):
		s.call("play", name)


func _play_and_haptic(name: String) -> void:
	if _screenshot_mode or name.is_empty():
		return
	var s := _sfx_node()
	if s != null and s.has_method("play_and_haptic"):
		s.call("play_and_haptic", name)
	elif s != null and s.has_method("play"):
		s.call("play", name)


# --- visuals -------------------------------------------------------------------

func _sync_visual() -> void:
	if not _built:
		return
	# Pack.
	var shake := Motion.shake_offset(_shake)
	_pack.visible = step != RevealPlan.STEP_SUMMARY
	_pack.size = _pack_size
	_pack.position = _pack_center - _pack_size * 0.5 + Vector2(shake, 0.0) \
			+ Vector2(_lean * Motion.PACK_LEAN_OFFSET_PX, 0.0)
	_pack.pivot_offset = _pack_size * 0.5
	_pack.rotation = deg_to_rad(_lean * Motion.PACK_LEAN_DEG)
	var mat := _pack_rip_mat()
	if mat != null:
		mat.set_shader_parameter("tear", _tear)
		mat.set_shader_parameter("rip_x", _rip_x)

	# The light coming out of the torn wrapper, in the pack's tease colour.
	var burst_scale := 1.0 + _burst * 0.22
	_backlight.size = _pack_size * burst_scale
	_backlight.position = _pack_center - _backlight.size * 0.5
	_backlight.modulate = Color(_tease, _burst * 0.55)
	_backlight.visible = _burst > 0.001 and step != RevealPlan.STEP_SUMMARY

	# The torn strip, falling away with a little rotation.
	_strip_rect.visible = _strip > 0.001 and step != RevealPlan.STEP_SUMMARY
	_strip_rect.size = Vector2(_pack_size.x, _pack_size.y * Motion.PACK_STRIP_FRACTION)
	_strip_rect.pivot_offset = Vector2(_strip_rect.size.x * 0.5, 0.0)
	_strip_rect.position = _pack_center - Vector2(_pack_size.x * 0.5, _pack_size.y * 0.5) \
			+ Vector2(shake * 0.35, _strip * _pack_size.y * Motion.PACK_STRIP_FALL_FRACTION)
	_strip_rect.rotation = deg_to_rad(-_strip * Motion.PACK_STRIP_TIP_DEG)
	_strip_rect.modulate = Color(1.0, 1.0, 1.0, 1.0 - _strip)
	var strip_mat := _strip_rect.material as ShaderMaterial
	if strip_mat != null:
		strip_mat.set_shader_parameter("slice", Motion.PACK_STRIP_FRACTION)
		strip_mat.set_shader_parameter("fall", _strip)

	# Screen dim: only the legendary build darkens the room.
	_dim_layer.color = Color(0.0, 0.0, 0.04, _dim * Motion.DIM_ALPHA)

	# The reveal stage.
	var revealing := step == RevealPlan.STEP_REVEALING
	_card_slot.visible = revealing
	_pity_tag.visible = revealing and _pity_shown
	_counter.visible = revealing
	if revealing:
		var rest := lerpf(Motion.CARD_REST_SCALE, 1.0, _card_out)
		var travel := (1.0 - _card_out) * _card_size.y * Motion.CARD_TRAVEL_FRACTION
		_card_slot.size = _card_size
		_card_slot.pivot_offset = _card_size * 0.5
		_card_slot.position = _card_center - _card_size * 0.5 - Vector2(0.0, travel)
		# The flip scales the whole slot so the back and the front swap at the
		# halfway point without either one stretching.
		_card_slot.scale = Vector2(rest * Motion.flip_scale(_flip), rest)
		var front := _flip >= 0.5
		_card_front.visible = front
		_card_back.visible = not front
		_glow_layer.visible = _glow > 0.001
		_glow_layer.size = _card_size * Motion.GLOW_SCALE
		_glow_layer.position = _card_center - _glow_layer.size * 0.5
		_glow_layer.modulate = Color(_tease, _glow * Motion.GLOW_ALPHA)
		_rays_rect.visible = _rays > 0.001
		_rays_rect.position = _card_center - _rays_rect.size * 0.5
		var rays_mat := _rays_mat()
		if rays_mat != null:
			rays_mat.set_shader_parameter("amount", _rays)
		_flash_rect.visible = _flash > 0.001
		_flash_rect.size = _card_size
		_flash_rect.position = _card_center - _card_size * 0.5
		_flash_rect.modulate = Color(1.0, 1.0, 1.0, _flash)
		_pity_tag.position = _card_center - Vector2(_pity_tag.size.x * 0.5,
				_card_size.y * 0.5 + 40.0)
		_counter.position = _card_center + Vector2(-_counter.size.x * 0.5,
				_card_size.y * 0.5 + 44.0)
	else:
		_glow_layer.visible = false
		_rays_rect.visible = false
		_flash_rect.visible = false

	_skip_button.visible = step != RevealPlan.STEP_SUMMARY
	_summary_root.visible = step == RevealPlan.STEP_SUMMARY


func _pack_rip_mat() -> ShaderMaterial:
	if _pack == null:
		return null
	return _pack.material as ShaderMaterial


func _rays_mat() -> ShaderMaterial:
	if _rays_rect == null:
		return null
	return _rays_rect.material as ShaderMaterial


func _placeholder_art() -> Dictionary:
	if _art_cache.is_empty():
		_art_cache = PlaceholderArtScript.build()
	return _art_cache


## The pull payload carries ids, not presentation data. GameState already
## holds the collection rows the server sent, so the reveal and the summary
## show the real name, set and art for cards the player owns; anything else
## (first pull before the collection refresh, screenshots) falls back to the
## procedural placeholder. No data is invented here.
func _lookup(card: Dictionary) -> Dictionary:
	if not is_inside_tree():
		return {}
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return {}
	var id := str(card.get("card_id", ""))
	for row in gs.collection:
		if row is Dictionary and str(row.get("card_id", "")) == id:
			return row
	return {}


func _meta_for(card: Dictionary) -> Dictionary:
	var row := _lookup(card)
	return {
		"name": str(row.get("name", "")),
		"set_id": str(row.get("set_id", "")),
	}


func _art_for(card: Dictionary) -> Dictionary:
	var row := _lookup(card)
	if row.is_empty():
		return _placeholder_art()
	return CardArt.textures_for(str(card.get("card_id", "")),
			str(card.get("rarity", "common")), str(row.get("art_path", "")))


# --- tweens --------------------------------------------------------------------

## Tween one animated property and repaint. Existing tween on the same property
## is killed first, so a re-triggered beat cannot fight the previous one.
func _tween(prop: String, from: float, to: float, ms: float, trans: int, ease_type: int) -> void:
	if _tree() == null:
		return
	var old: Variant = _tweens.get(prop)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := create_tween()
	t.tween_method(_set_progress.bind(prop), from, to, maxf(ms, 0.0) / 1000.0)
	t.set_trans(trans)
	t.set_ease(ease_type)
	_tweens[prop] = t


func _set_progress(value: float, prop: String) -> void:
	set(prop, value)
	_sync_visual()


func _cancel_tweens() -> void:
	for key in _tweens:
		var t: Variant = _tweens[key]
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	_tweens.clear()


func _tree() -> SceneTree:
	return get_tree() if is_inside_tree() else null


func _wait(seconds: float) -> void:
	var tree := _tree()
	if tree == null:
		return
	await tree.create_timer(maxf(seconds, 0.0)).timeout


# --- summary -------------------------------------------------------------------

## The summary is deliberately quiet: no motion, no sound, one way out. Every
## received card, small, with NEW on the ones the player did not own before.
func _build_summary() -> void:
	_clear_summary()
	var flags := RevealPlan.new_flags(_cards, _owned_keys)
	var cols := mini(Motion.SUMMARY_GRID_COLUMNS, maxi(_cards.size(), 1))
	_summary_grid.columns = cols
	for i in _cards.size():
		if not (_cards[i] is Dictionary):
			continue
		var card: Dictionary = _cards[i]
		var cell := _make_summary_cell(card, i < flags.size() and flags[i])
		_summary_grid.add_child(cell)
	if _summary_count != null:
		var fresh := 0
		for f in flags:
			if f:
				fresh += 1
		_summary_count.text = "%d cards · %d new" % [_cards.size(), fresh]


func _clear_summary() -> void:
	if _summary_grid == null:
		return
	for child in _summary_grid.get_children():
		child.queue_free()
		_summary_grid.remove_child(child)


func _make_summary_cell(card: Dictionary, is_new: bool) -> Control:
	var cell := VBoxContainer.new()
	cell.name = "Cell"
	cell.add_theme_constant_override("separation", 2)

	var holder := Control.new()
	holder.name = "Card"
	holder.custom_minimum_size = _summary_card_size()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var view := CardViewScene.instantiate() as CardView
	view.size = _summary_card_size()
	view.pivot_offset = _summary_card_size() * 0.5
	# No tilt input per cell: ten accelerometer readers on a summary grid is
	# waste, and a pinned tilt keeps the shot stable.
	view.use_tilt_override = true
	view.tilt_override = Vector2(0.35, -0.2)
	holder.add_child(view)
	view.set_card(str(card.get("rarity", "common")), _art_for(card), _meta_for(card))
	view.set_variant(str(card.get("variant", "none")))

	if is_new:
		var badge := Label.new()
		badge.name = "New"
		badge.text = "NEW"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", _tease)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -52.0
		badge.offset_top = 4.0
		badge.offset_right = -4.0
		badge.offset_bottom = 26.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(badge)

	cell.add_child(holder)
	return cell


func _summary_card_size() -> Vector2:
	var ext := _viewport()
	var cols := mini(Motion.SUMMARY_GRID_COLUMNS, maxi(_cards.size(), 1))
	var w := (ext.x * 0.90 - (cols - 1) * 10.0) / float(cols)
	return Vector2(w, w * 1.5)


# --- layout --------------------------------------------------------------------

func _viewport() -> Vector2:
	var ext := size
	if ext.x <= 0.0 or ext.y <= 0.0:
		# Detached (tests, screenshots before the first layout pass).
		ext = Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
				ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	return ext


func _layout() -> void:
	if not _built:
		return
	var ext := _viewport()
	_pack_size = Vector2(ext.x * 0.56, minf(ext.y * 0.38, ext.x * 0.78))
	_pack_center = Vector2(ext.x * 0.5, ext.y * 0.40)
	_card_size = Vector2(ext.x * 0.62, ext.x * 0.62 * 1.5)
	_card_size.y = minf(_card_size.y, ext.y * 0.40)
	_card_center = Vector2(ext.x * 0.5, ext.y * 0.44)
	_rays_rect.size = _card_size * 2.1
	_sync_visual()


# --- construction --------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_dim_layer = ColorRect.new()
	_dim_layer.name = "Dim"
	_dim_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_layer.color = Color(0.0, 0.0, 0.04, 0.0)
	_dim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim_layer)

	_backlight = ColorRect.new()
	_backlight.name = "Backlight"
	_backlight.material = _additive
	_backlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backlight.visible = false
	add_child(_backlight)

	_build_pack()
	_build_stage()
	_build_summary_panel()

	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "Skip"
	_skip_button.custom_minimum_size = Vector2(MIN_TAP_DP * 2.0, MIN_TAP_DP)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(_skip)
	_skip_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.offset_left = -MIN_TAP_DP * 2.0 - 16.0
	_skip_button.offset_top = -MIN_TAP_DP - 24.0
	_skip_button.offset_right = -16.0
	_skip_button.offset_bottom = -24.0
	add_child(_skip_button)

	resized.connect(_layout)
	_layout()


func _build_pack() -> void:
	var strip_mat := ShaderMaterial.new()
	strip_mat.shader = PackStripShader
	_strip_rect = ColorRect.new()
	_strip_rect.name = "Strip"
	_strip_rect.material = strip_mat
	_strip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_rect.visible = false
	add_child(_strip_rect)

	var pack_mat := ShaderMaterial.new()
	pack_mat.shader = PackTearShader
	_pack = ColorRect.new()
	_pack.name = "Pack"
	_pack.material = pack_mat
	_pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pack)
	pack_mat.set_shader_parameter("inner_light", _tease)


func _build_stage() -> void:
	_rays_rect = ColorRect.new()
	_rays_rect.name = "Rays"
	var rays_mat := ShaderMaterial.new()
	rays_mat.shader = RevealRaysShader
	_rays_rect.material = rays_mat
	_rays_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays_rect.visible = false
	add_child(_rays_rect)

	_glow_layer = ColorRect.new()
	_glow_layer.name = "Glow"
	_glow_layer.material = _additive
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_layer.visible = false
	add_child(_glow_layer)

	_card_slot = Control.new()
	_card_slot.name = "CardSlot"
	_card_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_slot.visible = false
	add_child(_card_slot)

	_card_back = Panel.new()
	_card_back.name = "CardBack"
	_card_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.086, 0.106, 0.243)
	back_style.border_color = Color(0.52, 0.24, 0.62)
	back_style.set_border_width_all(4)
	back_style.set_corner_radius_all(16)
	# A plain pattern on the back, not art: the front is the reward.
	back_style.draw_center = true
	_card_back.add_theme_stylebox_override("panel", back_style)
	_card_slot.add_child(_card_back)

	_card_front = CardViewScene.instantiate() as CardView
	_card_front.name = "CardFront"
	_card_front.use_tilt_override = true
	_card_front.tilt_override = Vector2(0.45, -0.25)
	_card_front.visible = false
	_card_slot.add_child(_card_front)
	# Anchors applied AFTER add_child: a preset set on a parentless scene
	# instance keeps the .tscn's default offsets and renders oversized.
	_card_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_flash_rect = ColorRect.new()
	_flash_rect.name = "Flash"
	_flash_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.visible = false
	add_child(_flash_rect)

	_pity_tag = Label.new()
	_pity_tag.name = "PityTag"
	_pity_tag.text = "Pity!"
	_pity_tag.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	_pity_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pity_tag.visible = false
	add_child(_pity_tag)

	_counter = Label.new()
	_counter.name = "Counter"
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.visible = false
	add_child(_counter)


func _build_summary_panel() -> void:
	_summary_root = Control.new()
	_summary_root.name = "Summary"
	_summary_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summary_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_root.visible = false
	add_child(_summary_root)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_root.add_child(centre)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 18)
	centre.add_child(col)

	_summary_count = Label.new()
	_summary_count.name = "Count"
	_summary_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_summary_count)

	_summary_grid = GridContainer.new()
	_summary_grid.name = "Grid"
	_summary_grid.add_theme_constant_override("h_separation", 10)
	_summary_grid.add_theme_constant_override("v_separation", 12)
	col.add_child(_summary_grid)

	_done_button = Button.new()
	_done_button.name = "DoneButton"
	_done_button.text = "Done"
	_done_button.custom_minimum_size = Vector2(MIN_TAP_DP * 3.0, MIN_TAP_DP)
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.pressed.connect(_on_done)
	var done_row := CenterContainer.new()
	done_row.name = "DoneRow"
	done_row.add_child(_done_button)
	col.add_child(done_row)


# --- screenshots ---------------------------------------------------------------
## One fixed ten-pull, so every capture and every reviewer sees the same moment:
## four commons, three rares, a pity epic, a rainbow epic, and a gold legendary
## holo last. No randomness and no network.

static func demo_pull() -> Dictionary:
	return {
		"cards": [
			{"user_card_id": "u1", "card_id": "aurora-late", "rarity": "common",
				"variant": "none", "pity": 0},
			{"user_card_id": "u2", "card_id": "neon-latte", "rarity": "common",
				"variant": "none", "pity": 0},
			{"user_card_id": "u3", "card_id": "velvet-static", "rarity": "common",
				"variant": "none", "pity": 0},
			{"user_card_id": "u4", "card_id": "harbor-lantern", "rarity": "common",
				"variant": "none", "pity": 0},
			{"user_card_id": "u5", "card_id": "sable-rain", "rarity": "rare",
				"variant": "none", "pity": 0},
			{"user_card_id": "u6", "card_id": "mika-signal", "rarity": "rare",
				"variant": "silver", "pity": 0},
			{"user_card_id": "u7", "card_id": "opal-drive", "rarity": "rare",
				"variant": "none", "pity": 0},
			{"user_card_id": "u8", "card_id": "yuki-ghost", "rarity": "epic",
				"variant": "none", "pity": 1},
			{"user_card_id": "u9", "card_id": "rin-vending", "rarity": "epic",
				"variant": "rainbow", "pity": 0},
			{"user_card_id": "u10", "card_id": "seraph-gold", "rarity": "legendary",
				"variant": "gold", "pity": 0},
		],
		"gems": 1440,
		"pity": {"since_epic": 0, "since_legendary": 0},
	}


## Own two of the commons plus the silver rare, so the summary has to badge the
## other eight and leave those three alone.
static func demo_owned_keys() -> Array[String]:
	return [
		RevealPlan.owned_key("aurora-late", "none"),
		RevealPlan.owned_key("neon-latte", "none"),
		RevealPlan.owned_key("velvet-static", "none"),
		RevealPlan.owned_key("mika-signal", "silver"),
		RevealPlan.owned_key("yuki-ghost", "rainbow"),
	]


func screenshot_count() -> int:
	return 7


func screenshot_setup(i: int) -> String:
	_ensure_built()
	_screenshot_mode = true
	_cancel_tweens()
	_run += 1
	_cancel_tweens()
	_ripping = false
	var result := demo_pull()
	_cards = result["cards"]
	_beats = RevealPlan.build(_cards)
	_owned_keys = demo_owned_keys()
	_tease = RevealPlan.best_tease_color(_cards)
	_rip_x = 0.36
	_layout()
	var label := ""
	match i:
		0:
			label = "pack_closed"
			_pose(RevealPlan.STEP_CLOSED, -1)
		1:
			label = "mid_tear"
			_pose(RevealPlan.STEP_TEARING, -1)
			_seek({"_shake": 1.0, "_tear": 0.45, "_burst": 0.85})
		2:
			label = "strip_falling"
			_pose(RevealPlan.STEP_TEARING, -1)
			_seek({"_tear": 1.0, "_burst": 0.35, "_strip": 0.4})
		3:
			label = "mid_reveal_rare"
			_pose(RevealPlan.STEP_REVEALING, 4)
			_seek({"_card_out": 1.0, "_flip": 0.3})
		4:
			label = "legendary_buildup"
			_pose(RevealPlan.STEP_REVEALING, 9)
			_seek({"_card_out": 1.0, "_glow": 0.85, "_rays": 0.7, "_dim": 1.0})
		5:
			label = "legendary_revealed"
			_pose(RevealPlan.STEP_REVEALING, 9)
			_seek({"_card_out": 1.0, "_flip": 1.0, "_glow": 1.0, "_rays": 0.25, "_dim": 0.5})
		_:
			label = "summary"
			_go_summary()
	return label


## Jump to a step with no animation and no sound. Everything a captured frame
## needs, and nothing a running game would do.
func _pose(new_step: String, index: int) -> void:
	step = new_step
	beat_index = index
	_clear_summary()
	match new_step:
		RevealPlan.STEP_REVEALING:
			_prepare_beat()
		_:
			_reset_beat()
	_sync_visual()


## Set animated properties straight to fixed values. This is how the frames are
## captured: a tear at 45%, a flip at 30%, rays at 70% - all the same every run.
func _seek(values: Dictionary) -> void:
	for prop in values:
		set(str(prop), float(values[prop]))
	_sync_visual()