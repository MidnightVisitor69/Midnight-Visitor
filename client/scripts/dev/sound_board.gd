extends Control
## Dev-only sound board (M-001): one button per sound so the dev can audition
## the kit on a real phone before any animation is built on it. This is a
## developer tool and must never ship reachable from a release build.
##
## Layout follows the holo bench: stock Godot controls built in code, because
## design tokens are still a later task and this screen has no design.

const SfxScript := preload("res://scripts/audio/sfx.gd")
## Every sound in the kit, in the order the pack opening uses them.
const SOUNDS: Array[String] = [
	"tap", "pack_rustle", "card_slide", "card_flip",
	"pack_tear", "reveal_rare", "reveal_epic", "reveal_legendary",
	"holo_shimmer", "acquire", "gems",
]
## Haptic moments are their own row: they make no sound, so they need a button.
const HAPTIC_SOUNDS: Array[String] = ["pack_tear", "reveal_legendary"]

## Android's minimum tap target.
const MIN_TAP_DP := 48

const BG_COLOR := Color(0.03, 0.05, 0.12)
const PANEL_COLOR := Color(0.06, 0.09, 0.18, 0.94)

var _built := false
var _toggle: CheckButton
var _readout: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	_ensure_built()


# --- construction -----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var panel := PanelContainer.new()
	panel.name = "Board"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	scroll.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Sound board (dev only)"
	col.add_child(title)

	_toggle = CheckButton.new()
	_toggle.name = "SoundToggle"
	_toggle.text = "Sound on"
	_toggle.button_pressed = _sfx_enabled()
	_toggle.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.toggled.connect(_on_toggled)
	col.add_child(_toggle)

	col.add_child(_section("Sounds"))
	for s in SOUNDS:
		col.add_child(_sound_button(s))

	col.add_child(_section("Haptics"))
	for s in HAPTIC_SOUNDS:
		col.add_child(_haptic_button(s))

	_readout = Label.new()
	_readout.name = "Readout"
	_readout.text = "Last: -"
	col.add_child(_readout)


func _section(p_text: String) -> Label:
	var label := Label.new()
	label.text = p_text
	label.modulate = Color(1, 1, 1, 0.6)
	return label


func _sound_button(p_name: String) -> Button:
	var b := Button.new()
	b.name = "Btn_" + p_name
	b.text = p_name
	b.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_on_sound_pressed.bind(p_name))
	_buttons.append(b)
	return b


func _haptic_button(p_name: String) -> Button:
	var b := Button.new()
	b.name = "Haptic_" + p_name
	b.text = "%s (%d ms)" % [p_name, int(SfxScript.HAPTIC_MS.get(p_name, 0))]
	b.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_on_haptic_pressed.bind(p_name))
	_buttons.append(b)
	return b


# --- action -----------------------------------------------------------------

func _on_sound_pressed(p_name: String) -> void:
	var sfx := _sfx()
	if sfx == null:
		return
	sfx.play(p_name)
	if _readout != null:
		_readout.text = "Last: %s" % p_name


func _on_haptic_pressed(p_name: String) -> void:
	var sfx := _sfx()
	if sfx == null:
		return
	sfx.haptic(p_name)
	if _readout != null:
		_readout.text = "Haptic: %s" % p_name


func _on_toggled(p_on: bool) -> void:
	var sfx := _sfx()
	if sfx != null:
		sfx.set_enabled(p_on)
	# A muted board that claims to be on is worse than no board.
	_toggle.text = "Sound on" if p_on else "Sound off"
	for b in _buttons:
		b.disabled = not p_on


func _sfx() -> Node:
	# /root lookups error while the board is built detached in a test.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Sfx")


func _sfx_enabled() -> bool:
	var sfx := _sfx()
	return true if sfx == null else bool(sfx.get("enabled"))


# --- readouts (used by tests) -----------------------------------------------

func sound_buttons() -> Array[Button]:
	_ensure_built()
	return _buttons


func sounds_offered() -> Array[String]:
	_ensure_built()
	return SOUNDS


func screenshot_count() -> int:
	return 1


func screenshot_setup(_i: int) -> String:
	_ensure_built()
	return "sound_board"