extends Control
## Dev-only holo test bench (AGENTS.md next task 2): one placeholder CardView
## plus a plain debug menu to switch rarity, foil variant, tilt source and foil
## intensity. Stock Godot controls on purpose: design tokens do not exist yet
## (AGENTS.md next task 3) and this screen must never ship enabled
## (gate: DevFlags.START_IN_HOLO_TEST).
##
## State lives here and nowhere else; every control writes through one set_
## method, which keeps the menu and the CardView from disagreeing.

const CardViewScene := preload("res://scenes/card/card_view.tscn")

const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]
const TILT_SOURCES: Array[String] = ["device", "drag"]
## Android's minimum tap target; the menu lives in the thumb zone.
const MIN_TAP_DP := 48
## Card fills ~80% of the phone width, portrait 2:3.
const CARD_WIDTH_FRACTION := 0.8
const CARD_ASPECT := 1.5
## Menu occupies the bottom third of the screen.
const MENU_TOP := 2.0 / 3.0

const BG_COLOR := Color(0.03, 0.05, 0.12)
const MENU_COLOR := Color(0.06, 0.09, 0.18, 0.94)

# --- state -----------------------------------------------------------------

var rarity := "common"
var variant := "none"
var tilt_source := "drag"
var intensity := 1.0
var menu_visible := true

var _art: Dictionary = {}
var _card: CardView
var _menu: PanelContainer
var _show_button: Button
var _slider: HSlider
var _int_value: Label
var _note_holo: Label
var _note_tilt: Label
var _readout: Label
var _rarity_buttons: Dictionary = {}
var _holo_buttons: Dictionary = {}
var _tilt_buttons: Dictionary = {}
var _controls: Array[Control] = []

var _built := false
var _dragging := false
var _drag_accum := Vector2.ZERO
var _drag_target := Vector2.ZERO
var _drag_tilt := Vector2.ZERO

## Placeholder textures are expensive to draw; one cache shared by every
## instance (the screenshot run and each test build the bench).
static var _art_cache: Dictionary = {}


# --- pure rules ------------------------------------------------------------

## Variants the rarity may show. Commons only get "none" (AGENTS.md holo rule).
static func allowed_variants(p_rarity: String) -> PackedStringArray:
	if p_rarity == "common":
		return PackedStringArray(["none"])
	return PackedStringArray(HoloVariants.VARIANTS)


## Drive tilt from the accelerometer only when there is one.
static func has_accelerometer() -> bool:
	return OS.has_feature("mobile")


static func _placeholder_art() -> Dictionary:
	if _art_cache.is_empty():
		_art_cache = PlaceholderArt.build()
	return _art_cache


func _ready() -> void:
	_ensure_built()


# --- one method per control ------------------------------------------------

func set_rarity(p_rarity: String) -> void:
	_ensure_built()
	rarity = p_rarity
	# Commons cannot hold a foil, so drop any held variant before drawing.
	if not allowed_variants(rarity).has(variant):
		variant = "none"
	_card.set_card(rarity, _art)
	_card.set_variant(variant)
	_apply_intensity()
	_sync_all_rows()


func set_variant(p_variant: String) -> void:
	_ensure_built()
	variant = p_variant if allowed_variants(rarity).has(p_variant) else "none"
	_card.set_variant(variant)
	_apply_intensity()
	_sync_all_rows()


func set_tilt_source(p_source: String) -> void:
	_ensure_built()
	# "device" needs an accelerometer; fall back to drag instead of lying.
	tilt_source = p_source if p_source in TILT_SOURCES else "drag"
	if tilt_source == "device" and not has_accelerometer():
		tilt_source = "drag"
	_apply_tilt_source()
	_sync_all_rows()


func set_intensity(p_value: float) -> void:
	_ensure_built()
	intensity = clampf(p_value, 0.0, 1.0)
	_apply_intensity()
	_sync_intensity()


func set_menu_visible(p_visible: bool) -> void:
	_ensure_built()
	menu_visible = p_visible
	_menu.visible = menu_visible
	_show_button.visible = not menu_visible


# --- readouts ---------------------------------------------------------------

## Every interactive control in the debug menu (used by the tap-target test).
func menu_controls() -> Array[Control]:
	_ensure_built()
	return _controls


## True when the sensor option is greyed out because there is no accelerometer.
func device_option_disabled() -> bool:
	_ensure_built()
	return (_tilt_buttons["device"] as Button).disabled


## True when the "no accelerometer" note is on screen.
func tilt_note_shown() -> bool:
	_ensure_built()
	return _note_tilt.visible


## The foil material the CardView is currently using, or null.
func holo_material() -> ShaderMaterial:
	if _card == null:
		return null
	var path := _card.holo_shader_path()
	if path == "":
		return null
	var art_root := _card.get_child(0)
	if art_root == null:
		return null
	for child in art_root.get_children():
		if child is ColorRect:
			var mat := (child as ColorRect).material as ShaderMaterial
			if mat != null and mat.shader != null and mat.shader.resource_path == path:
				return mat
	return null


## Tilt the card is actually showing (override in drag mode, sensor otherwise).
func current_tilt() -> Vector2:
	if _card == null:
		return Vector2.ZERO
	if _card.use_tilt_override:
		return _card.tilt_override
	var node := _card.get_node_or_null("TiltInput")
	if node is TiltInput:
		return (node as TiltInput).tilt
	return Vector2.ZERO


# --- construction -----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Default to the sensor where there is one; drag is the desktop fallback.
	if has_accelerometer():
		tilt_source = "device"

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_art = _placeholder_art()
	_card = CardViewScene.instantiate()
	_card.name = "CardView"
	add_child(_card)
	_card.set_card(rarity, _art)
	_card.set_variant(variant)

	_menu = _build_menu()
	add_child(_menu)

	_show_button = _make_button("Show menu")
	_show_button.name = "ShowButton"
	_show_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_show_button.offset_left = -160.0
	_show_button.offset_top = -72.0
	_show_button.offset_right = -16.0
	_show_button.offset_bottom = -16.0
	_show_button.visible = false
	_show_button.pressed.connect(func() -> void: set_menu_visible(true))
	add_child(_show_button)

	resized.connect(_layout)
	_apply_tilt_source()
	_apply_intensity()
	_sync_all_rows()
	_layout()


func _build_menu() -> PanelContainer:
	var menu := PanelContainer.new()
	menu.name = "DebugMenu"
	menu.anchor_left = 0.0
	menu.anchor_top = MENU_TOP
	menu.anchor_right = 1.0
	menu.anchor_bottom = 1.0
	var style := StyleBoxFlat.new()
	style.bg_color = MENU_COLOR
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	menu.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	menu.add_child(col)

	var rarity_group := ButtonGroup.new()
	var rarity_row := _row("Rarity")
	col.add_child(rarity_row)
	for r in RARITIES:
		var b := _make_toggle(r.capitalize(), rarity_group)
		b.pressed.connect(func() -> void: set_rarity(r))
		rarity_row.add_child(b)
		_rarity_buttons[r] = b

	var holo_group := ButtonGroup.new()
	var holo_row := _row("Holo")
	col.add_child(holo_row)
	for v in HoloVariants.VARIANTS:
		var b := _make_toggle(v.capitalize(), holo_group)
		b.pressed.connect(func() -> void: set_variant(v))
		holo_row.add_child(b)
		_holo_buttons[v] = b

	_note_holo = _make_note("Holo needs rare or higher.")
	col.add_child(_note_holo)

	var tilt_group := ButtonGroup.new()
	var tilt_row := _row("Tilt")
	col.add_child(tilt_row)
	for s in TILT_SOURCES:
		var b := _make_toggle(s.capitalize(), tilt_group)
		b.pressed.connect(func() -> void: set_tilt_source(s))
		tilt_row.add_child(b)
		_tilt_buttons[s] = b

	_note_tilt = _make_note("No accelerometer: drag the card.")
	col.add_child(_note_tilt)

	var int_row := _row("Intensity")
	col.add_child(int_row)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = intensity
	_slider.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(v: float) -> void: set_intensity(v))
	int_row.add_child(_slider)
	_controls.append(_slider)
	_int_value = _make_note("1.00")
	_int_value.custom_minimum_size.x = 44.0
	int_row.add_child(_int_value)

	_readout = _make_note("FPS 0   tilt 0.00 / 0.00")
	col.add_child(_readout)

	var hide := _make_button("Hide menu")
	hide.pressed.connect(func() -> void: set_menu_visible(false))
	col.add_child(hide)
	return menu


func _row(p_label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = p_label
	label.custom_minimum_size.x = 78.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _make_toggle(p_text: String, p_group: ButtonGroup) -> Button:
	var b := _make_button(p_text)
	b.toggle_mode = true
	b.button_group = p_group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _make_button(p_text: String) -> Button:
	var b := Button.new()
	b.text = p_text
	b.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_controls.append(b)
	return b


func _make_note(p_text: String) -> Label:
	var label := Label.new()
	label.text = p_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- application ------------------------------------------------------------

func _apply_tilt_source() -> void:
	if _card == null:
		return
	# PASS so a tap on the card can still reach the bench in either mode.
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	if tilt_source == "device":
		_card.use_tilt_override = false
	else:
		_card.use_tilt_override = true
		_card.tilt_override = _drag_tilt


func _apply_intensity() -> void:
	var mat := holo_material()
	if mat != null:
		mat.set_shader_parameter("intensity", intensity)


func _sync_all_rows() -> void:
	for r in _rarity_buttons:
		(_rarity_buttons[r] as Button).button_pressed = (r == rarity)
	var allowed := allowed_variants(rarity)
	for v in _holo_buttons:
		var b := _holo_buttons[v] as Button
		b.disabled = not allowed.has(v)
		b.button_pressed = (v == variant)
	_note_holo.visible = rarity == "common"
	for s in _tilt_buttons:
		var b := _tilt_buttons[s] as Button
		b.disabled = s == "device" and not has_accelerometer()
		b.button_pressed = s == tilt_source
	_note_tilt.visible = not has_accelerometer()
	_sync_intensity()


func _sync_intensity() -> void:
	if _slider == null:
		return
	_slider.set_value_no_signal(intensity)
	_int_value.text = "%.2f" % intensity


func _layout() -> void:
	if _card == null:
		return
	var extents := size
	if extents.x <= 0.0 or extents.y <= 0.0:
		extents = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
			ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	# Card sits in the top two thirds; the menu owns the rest.
	var region := Vector2(extents.x, extents.y * MENU_TOP)
	var w := region.x * CARD_WIDTH_FRACTION
	var h := w * CARD_ASPECT
	if h > region.y:
		h = region.y
		w = h / CARD_ASPECT
	_card.size = Vector2(w, h)
	_card.position = (region - _card.size) * 0.5


# --- input ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _card != null and tilt_source == "drag":
		_drag_tilt = TiltInput.damp(_drag_tilt, _drag_target, TiltInput.DEFAULT_DAMP_RATE, delta)
		_card.tilt_override = _drag_tilt
	if _readout != null:
		var t := current_tilt()
		_readout.text = "FPS %d   tilt %.2f / %.2f" % [
			Engine.get_frames_per_second(), t.x, t.y]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_press((event as InputEventMouseButton).pressed)
	elif event is InputEventScreenTouch:
		_handle_press((event as InputEventScreenTouch).pressed)
	elif event is InputEventMouseMotion:
		_handle_drag((event as InputEventMouseMotion).relative)
	elif event is InputEventScreenDrag:
		_handle_drag((event as InputEventScreenDrag).relative)


func _handle_press(p_pressed: bool) -> void:
	if p_pressed:
		if not menu_visible:
			set_menu_visible(true)
			accept_event()
			return
		if tilt_source == "drag":
			_dragging = true
			_drag_accum = Vector2.ZERO
			accept_event()
	else:
		_dragging = false
		_drag_accum = Vector2.ZERO
		_drag_target = Vector2.ZERO


func _handle_drag(p_relative: Vector2) -> void:
	if tilt_source != "drag" or not _dragging:
		return
	_drag_accum += p_relative
	_drag_target = TiltInput.drag_to_tilt(_drag_accum)
	accept_event()


# --- screenshots ------------------------------------------------------------

func screenshot_count() -> int:
	return 3


func screenshot_setup(i: int) -> String:
	_ensure_built()
	match i:
		0:
			set_rarity("epic")
			set_variant("galaxy")
			set_menu_visible(true)
			return "epic_galaxy_menu"
		1:
			set_rarity("legendary")
			set_variant("gold")
			set_menu_visible(false)
			return "legendary_gold_no_menu"
		_:
			set_rarity("common")
			set_variant("none")
			set_menu_visible(true)
			return "common_none_holo_disabled"
