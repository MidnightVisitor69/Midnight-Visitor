extends Node
## Autoload `Settings` (D-003): the single source of truth for every player
## preference, persisted to user://settings.cfg, with one signal `changed(key)`.
##
## Why an autoload: the Settings screen, the card shaders, the pack opening and
## Sfx all need the same values, and none of them come from the server. Screens
## read the properties (Settings.reduce_motion), the screen writes them, and
## everything else listens for changed(key).
##
## Legacy: M-001's Sfx persisted [audio] enabled in this same file. That key is
## read on first load and mirrored on every save, so an old build and a new one
## agree (task: keep backward-compatible keys).
##
## Every setting has a real effect; there are no decorative toggles:
##   reduce_motion        -> Motion.reduced (idle off, essential beats <= 40 ms)
##   text_scale           -> theme font sizes
##   high_contrast        -> a stronger-contrast theme variant
##   holo_intensity       -> CardView foil strength
##   card_tilt_mode       -> TiltInput source (sensor / drag / off)
##   tilt_sensitivity     -> TiltInput response
##   battery_saver        -> 30 fps cap
##   sfx_volume           -> the SFX bus + Sfx.enabled
##   haptics_on           -> Sfx haptics

signal changed(key: String)

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_THEME_PATH := "res://theme/app_theme.tres"
## The legacy Sfx file used the [audio] enabled pair; kept as a mirror.
const LEGACY_SECTION := "audio"
const LEGACY_ENABLED := "enabled"
## Our own section, so the two never collide.
const SECTION := "settings"

## Named text sizes -> theme font scale. "default" is 1.0, so an untouched
## install draws exactly the token sizes.
const TEXT_SCALES := {"small": 0.9, "default": 1.0, "large": 1.15, "xlarge": 1.3}
const TEXT_SIZE_ORDER: Array[String] = ["small", "default", "large", "xlarge"]
const TEXT_SIZE_LABELS := {
	"small": "Small",
	"default": "Default",
	"large": "Large",
	"xlarge": "Extra large",
}
const TILT_MODES: Array[String] = ["gyroscope", "drag", "off"]
const TILT_MODE_LABELS := {
	"gyroscope": "Gyroscope",
	"drag": "Drag only",
	"off": "Off",
}

## Reduce motion is not "no motion": a state change still has to read. 40 ms is
## the task's ceiling for a beat that must survive.
const REDUCED_MOTION_MS := 40.0
## Battery saver caps the frame rate; 30 is the task's number.
const BATTERY_SAVER_FPS := 30

## Persisted keys and their defaults, in one table so save() cannot forget one.
const DEFAULTS := {
	"sfx_volume": 1.0,
	"haptics_on": true,
	"reduce_motion": false,
	"holo_intensity": 100,
	"card_tilt_mode": "gyroscope",
	"tilt_sensitivity": 0.5,
	"battery_saver": false,
	"text_scale": 1.0,
	"high_contrast": false,
	"colorblind_rarity": true,
	"quick_open": false,
	"skip_tear_animation": false,
	"confirm_spend_gems": true,
	"left_handed_layout": false,
}

## Overridable so tests round-trip through a throwaway file.
var config_path := CONFIG_PATH

var sfx_volume := 1.0:
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)
		_after_change("sfx_volume")

var haptics_on := true:
	set(value):
		haptics_on = value
		_after_change("haptics_on")

var reduce_motion := false:
	set(value):
		reduce_motion = value
		_after_change("reduce_motion")

var holo_intensity := 100:
	set(value):
		holo_intensity = clampi(int(round(value)), 0, 100)
		_after_change("holo_intensity")

var card_tilt_mode := "gyroscope":
	set(value):
		card_tilt_mode = value if TILT_MODES.has(value) else "gyroscope"
		_after_change("card_tilt_mode")

var tilt_sensitivity := 0.5:
	set(value):
		tilt_sensitivity = clampf(value, 0.0, 1.0)
		_after_change("tilt_sensitivity")

var battery_saver := false:
	set(value):
		battery_saver = value
		_after_change("battery_saver")

var text_scale := 1.0:
	set(value):
		text_scale = clampf(value, 0.5, 2.0)
		_after_change("text_scale")

var high_contrast := false:
	set(value):
		high_contrast = value
		_after_change("high_contrast")

var colorblind_rarity := true:
	set(value):
		colorblind_rarity = value
		_after_change("colorblind_rarity")

var quick_open := false:
	set(value):
		quick_open = value
		_after_change("quick_open")

var skip_tear_animation := false:
	set(value):
		skip_tear_animation = value
		_after_change("skip_tear_animation")

var confirm_spend_gems := true:
	set(value):
		confirm_spend_gems = value
		_after_change("confirm_spend_gems")

var left_handed_layout := false:
	set(value):
		left_handed_layout = value
		_after_change("left_handed_layout")

## True while reload() feeds values in, so setters neither save nor re-apply.
var _loading := false
## The theme we scale from; captured once so repeated applies never compound.
var _base_theme: Theme


func _ready() -> void:
	reload()


# --- reading / writing --------------------------------------------------------

## A typed, string-keyed read. `get` is a native Object method, so the keyed
## door is named value() instead of overriding it.
func value(key: String) -> Variant:
	return get(key)


## The one place a new value enters. Every setter funnels through here so the
## signal, the side effects and the save happen in exactly one order.
func _after_change(key: String) -> void:
	if _loading:
		return
	_apply_side_effect(key)
	_persist()
	changed.emit(key)


func reload() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(config_path) == OK
	_loading = true
	for key in DEFAULTS:
		var loaded: Variant = cfg.get_value(SECTION, key, DEFAULTS[key]) if ok else DEFAULTS[key]
		set(key, loaded)
	# Backward-compatible migration: an install that only ever wrote the old
	# Sfx toggle gets it turned into a volume.
	if ok and not cfg.has_section_key(SECTION, "sfx_volume"):
		var legacy_on := bool(cfg.get_value(LEGACY_SECTION, LEGACY_ENABLED, true))
		sfx_volume = 1.0 if legacy_on else 0.0
	_loading = false
	_apply_all()
	# Let the screen (and anything else listening) prime itself from disk.
	for key in DEFAULTS:
		changed.emit(key)


func _persist() -> void:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		cfg.set_value(SECTION, key, get(key))
	# The mirror an older Sfx build still reads.
	cfg.set_value(LEGACY_SECTION, LEGACY_ENABLED, sfx_volume > 0.0)
	cfg.save(config_path)


# --- derived helpers ----------------------------------------------------------

## The named size that matches the current scale ("default" when it matches
## none, which also covers a hand-edited file).
func text_size_name() -> String:
	for name in TEXT_SIZE_ORDER:
		if is_equal_approx(float(TEXT_SCALES[name]), text_scale):
			return name
	return "default"


func set_text_size(name: String) -> void:
	text_scale = float(TEXT_SCALES.get(name, 1.0))


func tilt_mode_label() -> String:
	return str(TILT_MODE_LABELS.get(card_tilt_mode, card_tilt_mode))


## An essential animation's duration after the reduced-motion rule. Screens that
## must still confirm a tap call this instead of the raw Motion constant.
func motion_ms(base_ms: float) -> float:
	return minf(base_ms, REDUCED_MOTION_MS) if reduce_motion else base_ms


# --- side effects -------------------------------------------------------------

func _apply_all() -> void:
	for key in DEFAULTS:
		_apply_side_effect(key)


func _apply_side_effect(key: String) -> void:
	match key:
		"reduce_motion":
			Motion.reduced = reduce_motion
		"holo_intensity":
			CardView.holo_scale = clampf(float(holo_intensity) / 100.0, 0.0, 1.0)
		"card_tilt_mode", "tilt_sensitivity":
			TiltInput.tilt_mode = card_tilt_mode
			TiltInput.sensitivity = tilt_sensitivity
		"battery_saver":
			Engine.max_fps = BATTERY_SAVER_FPS if battery_saver else 0
			# Lighter work per frame: no particle accents anywhere.
			CardView.particles_enabled = not battery_saver
		"sfx_volume", "haptics_on":
			_apply_sfx()
		"text_scale", "high_contrast":
			apply_theme()
		_:
			pass


func _apply_sfx() -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		# A muted bus is -inf dB; floor at a hair above silence.
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(sfx_volume, 0.0001)))
	var sfx := _autoload("Sfx")
	if sfx != null and sfx.has_method("apply_settings"):
		sfx.call("apply_settings", sfx_volume > 0.0, haptics_on)


func _autoload(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/" + node_name)


# --- theme --------------------------------------------------------------------

## The project theme with the text scale (and the high-contrast variant) baked
## in. Pure: no tree needed, so a test can compare two scales directly.
func theme_for(base: Theme) -> Theme:
	if base == null:
		base = load(DEFAULT_THEME_PATH) as Theme
	if base == null:
		return null
	var t: Theme = base.duplicate(true)
	_scale_fonts(t, base)
	if high_contrast:
		_apply_high_contrast(t)
	return t


func _scale_fonts(t: Theme, base: Theme) -> void:
	if is_equal_approx(text_scale, 1.0):
		return
	t.default_font_size = maxi(1, int(round(float(base.default_font_size) * text_scale)))
	for type_name in base.get_type_list():
		for font_size_name in base.get_font_size_list(type_name):
			var size := base.get_font_size(font_size_name, type_name)
			t.set_font_size(font_size_name, type_name,
					maxi(1, int(round(float(size) * text_scale))))


## Stronger outlines and text contrast, from the same tokens: secondary text
## becomes primary and every panel border thickens by one pixel.
func _apply_high_contrast(t: Theme) -> void:
	var strong := Tokens.color(&"text_primary")
	for type_name in t.get_type_list():
		for color_name in t.get_color_list(type_name):
			if str(color_name).begins_with("font"):
				t.set_color(color_name, type_name, strong)
		for sb_name in t.get_stylebox_list(type_name):
			var sb := t.get_stylebox(sb_name, type_name)
			if sb is StyleBoxFlat:
				var flat: StyleBoxFlat = sb
				flat.border_width_top = maxi(flat.border_width_top, 1)
				flat.border_width_left = maxi(flat.border_width_left, 1)
				flat.border_width_right = maxi(flat.border_width_right, 1)
				flat.border_width_bottom = maxi(flat.border_width_bottom, 1)
				flat.border_color = Tokens.color(&"outline")


## Push the current scale/high-contrast onto the running window theme.
func apply_theme() -> void:
	var tree := get_tree() if is_inside_tree() else null
	var win: Window = tree.root if tree != null else null
	if win == null:
		return
	if _base_theme == null:
		_base_theme = win.theme
	if _base_theme == null:
		_base_theme = load(DEFAULT_THEME_PATH) as Theme
	if _base_theme == null:
		return
	win.theme = theme_for(_base_theme)
