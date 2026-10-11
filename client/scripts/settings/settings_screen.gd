extends Control
## Settings screen (D-003): one full-screen, sectioned, scrollable page behind a
## gear in the shell's top bar. Every option is wired to a real behaviour through
## the Settings autoload; there are no decorative toggles.
##
## Structure: a back button + title in the top bar (thumb-reachable), then one
## SectionHeader + panel per group. Rows are 48 dp and a whole row is the tap
## target, not a tiny switch. Every interactive control carries an
## accessibility_name/description for Godot's screen reader, and a visible focus
## outline for keyboard/controller.
##
## Tests and screenshots build it offline with set_preview_data(); nothing here
## reaches the network unless the player actually signs out or deletes.
##
## Screenshot states: top, middle, bottom, delete-account confirm.

signal closed

const SettingsScript := preload("res://scripts/settings/settings.gd")
const FormatScript := preload("res://scripts/app/format.gd")
const PackMathScript := preload("res://scripts/app/pack_math.gd")

const APP_VERSION_FALLBACK := "0.1.0-alpha"
const START_SCENE := "res://scenes/main.tscn"
## Android's minimum tap target; every row meets it (AGENTS.md thumb-first).
const MIN_ROW := 48.0

var settings: Node = null

## 0 idle, 1 first confirm, 2 final confirm, 3 committed. Deleting needs two.
var delete_stage := 0
var delete_committed := false
var sign_out_stage := 0
var sign_out_committed := false

var _preview := false
var _home: Dictionary = {}
var _banners: Array = []
var _player_id := ""
var _built := false
var _screenshot_mode := false
var _scroll_target := -1

var _scroll: ScrollContainer
var _page: VBoxContainer
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _overlay_confirm: Button
var _overlay_cancel: Button
var _overlay_cb := Callable()

var _rows: Array[Control] = []
var _controls: Array[Control] = []
var _state_labels: Dictionary = {}   # setting key -> toggle state Label
var _value_labels: Dictionary = {}   # setting key (slider) or name -> Label
var _option_nodes: Dictionary = {}   # setting key -> OptionButton
var _slider_nodes: Dictionary = {}   # setting key -> HSlider


func _ready() -> void:
	_ensure_built()
	if _preview:
		return
	var s := _settings_node()
	if s != null and not s.changed.is_connected(_on_setting_changed):
		s.changed.connect(_on_setting_changed)
	var gs := _game_state()
	if gs != null:
		if not gs.home_changed.is_connected(_on_home_changed):
			gs.home_changed.connect(_on_home_changed)
		_home = gs.get("home")
		_banners = gs.get("banners")
	_refresh_info_rows()


# --- offline seam -------------------------------------------------------------

## Tests and screenshots: feed the home payload, parsed banners and a player id,
## exactly as GameState/Api produce them. Never touches the network.
func set_preview_data(home: Dictionary, banners: Array, player_id := "") -> void:
	_ensure_built()
	_preview = true
	_home = home.duplicate(true)
	_banners = banners.duplicate(true)
	_player_id = player_id
	_refresh_info_rows()


func _on_home_changed() -> void:
	var gs := _game_state()
	if gs != null:
		_home = gs.get("home")
		_banners = gs.get("banners")
	_refresh_info_rows()


# --- readouts (tests) ---------------------------------------------------------

## Every setting row, in draw order.
func rows() -> Array[Control]:
	_ensure_built()
	return _rows


## Every interactive control on the screen (buttons, sliders, option buttons).
func interactive_controls() -> Array[Control]:
	_ensure_built()
	return _controls


func overlay_visible() -> bool:
	_ensure_built()
	return _overlay.visible


func delete_button() -> Button:
	_ensure_built()
	return _value_labels["delete_button"] as Button


# --- delete / sign-out (two confirmations) ------------------------------------

func request_delete() -> void:
	if delete_stage != 0:
		return
	delete_stage = 1
	_show_overlay("Delete your account?",
			"Deleting removes your account, your cards and your progress from the server. This cannot be undone.",
			"Continue", "Cancel", confirm_delete)


## The single entry point for both confirmations; the overlay's Confirm button
## and the tests both call it, so a one-step delete cannot slip through.
func confirm_delete() -> void:
	match delete_stage:
		1:
			_delete_second_step()
		2:
			_commit_delete()
		_:
			pass


func cancel_delete() -> void:
	delete_stage = 0
	_hide_overlay()


func _delete_second_step() -> void:
	delete_stage = 2
	_show_overlay("Delete everything, forever?",
			"There is no recovery and no refund: your collection is gone for good.",
			"Delete forever", "Keep my account", confirm_delete)


func _commit_delete() -> void:
	delete_stage = 3
	_hide_overlay()
	_perform_delete()


func _perform_delete() -> void:
	var sb := _supabase()
	if _preview or sb == null:
		# Offline (tests): the decision is recorded, nothing is sent.
		delete_committed = true
		closed.emit()
		return
	var res: Dictionary = await Api.delete_my_account(sb)
	delete_committed = bool(res.get("ok", false))
	if delete_committed:
		sb.call("sign_out")
		_return_to_start()


func request_sign_out() -> void:
	if sign_out_stage != 0:
		return
	sign_out_stage = 1
	_show_overlay("Sign out?",
			"You can sign back in later, but this device forgets your session.",
			"Sign out", "Cancel", confirm_sign_out)


func confirm_sign_out() -> void:
	if sign_out_stage == 0:
		return
	sign_out_stage = 2
	_hide_overlay()
	var sb := _supabase()
	if _preview or sb == null:
		sign_out_committed = true
		closed.emit()
		return
	sb.call("sign_out")
	_return_to_start()


func _return_to_start() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree != null:
		tree.change_scene_to_file(START_SCENE)


# --- construction -------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := AppBackground.new()
	bg.name = "Background"
	add_child(bg)

	_build_top_bar()

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = Tokens.space(&"s48") + Tokens.space(&"s24")
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.space(&"s24"))
	margin.add_theme_constant_override("margin_top", Tokens.space(&"s16"))
	margin.add_theme_constant_override("margin_bottom", Tokens.space(&"s48"))
	_scroll.add_child(margin)

	_page = VBoxContainer.new()
	_page.name = "Page"
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", Tokens.space(&"s24"))
	margin.add_child(_page)

	_build_audio()
	_build_display_motion()
	_build_readability()
	_build_pack_opening()
	_build_controls()
	_build_account()
	_build_info()

	_build_overlay()
	_refresh_info_rows()
	set_process(false)


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.anchor_right = 1.0
	bar.offset_bottom = Tokens.space(&"s48") + Tokens.space(&"s24")
	add_child(bar)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", Tokens.space(&"s12"))
	bar.add_child(row)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.theme_type_variation = "ButtonGhost"
	back.focus_mode = Control.FOCUS_ALL
	back.custom_minimum_size = Vector2(0.0, MIN_ROW)
	back.add_theme_stylebox_override("focus", _focus_style())
	back.pressed.connect(_on_back)
	_a11y(back, "Back", "Close settings and return to the game")
	row.add_child(back)
	_controls.append(back)

	var title := Label.new()
	title.name = "Title"
	title.text = "Settings"
	title.theme_type_variation = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)


func _build_audio() -> void:
	var col := _section("Audio")
	var s := _settings_node()
	var volume := float(s.get("sfx_volume")) if s != null else 1.0
	_slider_row(col, "Sound effects volume", "sfx_volume", 0.0, 100.0, 1.0,
			volume * 100.0, _on_sfx_slider, _format_percent, "Sound effects volume")
	_toggle_row(col, "Haptics", "haptics_on", "Vibration on pack tear and legendary reveals")


func _build_display_motion() -> void:
	var col := _section("Display & motion")
	_toggle_row(col, "Reduce motion", "reduce_motion",
			"Shortens non-essential animation, stops breathing and shimmer")
	var holo := int(_settings_node().get("holo_intensity")) if _settings_node() != null else 100
	_slider_row(col, "Holo intensity", "holo_intensity", 0.0, 100.0, 1.0,
			float(holo), _on_holo_slider, _format_percent, "Strength of the card foil")
	_option_row(col, "Card tilt", "card_tilt_mode", SettingsScript.TILT_MODES,
			SettingsScript.TILT_MODE_LABELS, "How the card follows your hand")
	var tilt := float(_settings_node().get("tilt_sensitivity")) if _settings_node() != null else 0.5
	_slider_row(col, "Tilt sensitivity", "tilt_sensitivity", 0.0, 100.0, 1.0,
			tilt * 100.0, _on_tilt_slider, _format_percent, "How far the card leans")
	_action_row(col, "Re-center tilt", _on_recenter, "Treat the current hold as level")
	_toggle_row(col, "Battery saver", "battery_saver",
			"30 fps cap, particles off and lighter shaders")


func _build_readability() -> void:
	var col := _section("Readability")
	_option_row(col, "Text size", "text_size", SettingsScript.TEXT_SIZE_ORDER,
			SettingsScript.TEXT_SIZE_LABELS, "Scales the theme font sizes")
	_toggle_row(col, "High contrast", "high_contrast",
			"Stronger outlines and brighter secondary text")
	_toggle_row(col, "Colorblind-friendly rarity", "colorblind_rarity",
			"Always show the rarity shape and label, never colour alone")


func _build_pack_opening() -> void:
	var col := _section("Pack opening")
	_toggle_row(col, "Quick open", "quick_open",
			"Reveal all cards at once instead of one at a time")
	_toggle_row(col, "Skip tear animation", "skip_tear_animation",
			"Open the pack without the rip animation")
	_toggle_row(col, "Confirm before spending gems", "confirm_spend_gems",
			"Ask before a pull that spends gems")


func _build_controls() -> void:
	var col := _section("Controls")
	_toggle_row(col, "Left-handed layout", "left_handed_layout",
			"Mirror the floating secondary controls to the other side")


func _build_account() -> void:
	var col := _section("Account")
	_value_row(col, "Status", "guest")
	_value_row(col, "Player ID", "player_id")
	_action_row(col, "Copy player ID", _on_copy_id,
			"Copy your player ID for support")
	_action_row(col, "Sign out", _on_sign_out, "End this session on this device")
	var del := _action_row(col, "Delete account", _on_delete,
			"Permanently delete your account and every card")
	_value_labels["delete_button"] = del


func _build_info() -> void:
	var col := _section("Info")
	_action_row(col, "Drop rates", _on_drop_rates,
			"Full rarity, pity and holo odds")
	_value_row(col, "Lifetime spending", "lifetime")
	_action_row(col, "Privacy policy", _on_privacy, "How your data is handled")
	_action_row(col, "Terms of service", _on_terms, "The rules for using the game")
	_value_row(col, "Credits", "credits")
	_value_row(col, "Version", "version")


# --- section + row builders ---------------------------------------------------

func _section(title: String) -> VBoxContainer:
	var head := SectionHeader.new()
	head.name = "Header_" + title
	_page.add_child(head)
	head.setup(title)

	var panel := PanelContainer.new()
	panel.name = "Panel_" + title
	_page.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Rows"
	col.add_theme_constant_override("separation", Tokens.space(&"s8"))
	panel.add_child(col)
	return col


## A full-row toggle: the whole 48-dp row is the button, so a thumb anywhere on
## it flips the setting (task: tap anywhere on the row).
func _toggle_row(parent: VBoxContainer, label: String, key: String, desc: String) -> Button:
	var row := Button.new()
	row.name = "Row_" + key
	row.toggle_mode = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.theme_type_variation = "ButtonGhost"
	row.focus_mode = Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0.0, MIN_ROW)
	row.add_theme_stylebox_override("focus", _focus_style())
	row.text = label
	_a11y(row, label, desc)

	var state := Label.new()
	state.name = "State"
	state.theme_type_variation = "Caption"
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	state.offset_left = -160.0
	state.offset_right = -Tokens.space(&"s16")
	state.offset_top = -12.0
	state.offset_bottom = 12.0
	row.add_child(state)

	var s := _settings_node()
	row.button_pressed = bool(s.get(key)) if s != null else bool(SettingsScript.DEFAULTS[key])
	_paint_toggle(state, row.button_pressed)
	row.toggled.connect(_on_toggle.bind(key))
	_state_labels[key] = state

	parent.add_child(row)
	_rows.append(row)
	_controls.append(row)
	return row


func _slider_row(parent: VBoxContainer, label: String, key: String,
		min_v: float, max_v: float, step: float, initial: float,
		handler: Callable, fmt: Callable, desc: String) -> Control:
	var row := VBoxContainer.new()
	row.name = "Row_" + key
	row.custom_minimum_size = Vector2(0.0, MIN_ROW)

	var head := HBoxContainer.new()
	head.name = "Head"
	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = "Body"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	var value := Label.new()
	value.name = "Value"
	value.theme_type_variation = "Caption"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text = str(fmt.call(initial))
	head.add_child(value)
	row.add_child(head)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.focus_mode = Control.FOCUS_ALL
	slider.custom_minimum_size = Vector2(0.0, MIN_ROW)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.add_theme_stylebox_override("focus", _focus_style())
	_a11y(slider, label, desc)
	slider.value_changed.connect(handler)
	row.add_child(slider)

	parent.add_child(row)
	_rows.append(row)
	_controls.append(slider)
	_value_labels[key] = value
	_slider_nodes[key] = slider
	return row


func _option_row(parent: VBoxContainer, label: String, key: String,
		values: Array, labels: Dictionary, desc: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	row.custom_minimum_size = Vector2(0.0, MIN_ROW)

	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = "Body"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var opt := OptionButton.new()
	opt.name = "Option"
	opt.focus_mode = Control.FOCUS_ALL
	opt.custom_minimum_size = Vector2(220.0, MIN_ROW)
	opt.add_theme_stylebox_override("focus", _focus_style())
	for v in values:
		opt.add_item(str(labels.get(v, v)))
	var current := _current_option_value(key)
	opt.select(maxi(values.find(current), 0))
	_a11y(opt, label, desc)
	opt.item_selected.connect(_on_option.bind(key, values))

	row.add_child(opt)
	parent.add_child(row)
	_rows.append(row)
	_controls.append(opt)
	_option_nodes[key] = opt
	return opt


func _action_row(parent: VBoxContainer, label: String, handler: Callable,
		desc: String, variation := "ButtonGhost") -> Button:
	var row := Button.new()
	row.name = "Row_" + label.to_snake_case()
	row.text = label
	row.theme_type_variation = variation
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0.0, MIN_ROW)
	row.add_theme_stylebox_override("focus", _focus_style())
	row.pressed.connect(handler)
	_a11y(row, label, desc)
	parent.add_child(row)
	_rows.append(row)
	_controls.append(row)
	return row


## A quiet label over a value; not interactive, so no a11y name is needed.
func _value_row(parent: VBoxContainer, label: String, value_name: String) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_" + value_name
	row.custom_minimum_size = Vector2(0.0, MIN_ROW)

	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = "Body"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var value := Label.new()
	value.name = "Value"
	value.theme_type_variation = "Caption"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	parent.add_child(row)
	_rows.append(row)
	_value_labels[value_name] = value
	return value


# --- row handlers -------------------------------------------------------------

func _on_toggle(pressed: bool, key: String) -> void:
	_write_setting(key, pressed)
	if _state_labels.has(key):
		_paint_toggle(_state_labels[key] as Label, pressed)


func _paint_toggle(label: Label, on: bool) -> void:
	label.text = "On" if on else "Off"
	label.add_theme_color_override("font_color",
			Tokens.color(&"accent_secondary") if on else Tokens.color(&"text_secondary"))


func _on_option(index: int, key: String, values: Array) -> void:
	var value: Variant = values[index]
	if key == "text_size":
		_write_setting("text_scale", float(SettingsScript.TEXT_SCALES.get(str(value), 1.0)))
	else:
		_write_setting(key, value)


func _on_sfx_slider(value: float) -> void:
	_write_setting("sfx_volume", value / 100.0)
	_value_labels["sfx_volume"].text = _format_percent(value)


func _on_holo_slider(value: float) -> void:
	_write_setting("holo_intensity", int(round(value)))
	_value_labels["holo_intensity"].text = _format_percent(value)


func _on_tilt_slider(value: float) -> void:
	_write_setting("tilt_sensitivity", value / 100.0)
	_value_labels["tilt_sensitivity"].text = _format_percent(value)


func _on_recenter() -> void:
	TiltInput.recenter()
	_toast("Tilt re-centered")


func _on_copy_id() -> void:
	var id := _player_id if not _player_id.is_empty() else str(_supabase().get("user_id"))
	DisplayServer.clipboard_set(id)
	_toast("Player ID copied" if not id.is_empty() else "No player ID yet")


func _on_delete() -> void:
	request_delete()


func _on_sign_out() -> void:
	request_sign_out()


func _on_back() -> void:
	closed.emit()


func _on_drop_rates() -> void:
	var b := _first_banner()
	if b.is_empty():
		_show_overlay("Drop rates",
				"Odds appear here once the server publishes a banner.", "Close", "", Callable())
		return
	var lines: Array[String] = [
		"Rarity: " + PackMathScript.rarity_odds_text(b.get("odds", {})),
		"Pity: " + PackMathScript.pity_text(_home.get("pity", {}), b.get("pity", {})),
		"Holo: " + PackMathScript.holo_odds_text(b.get("holo_odds", {})),
		"",
		"Pity carries across every banner. Odds are published before any purchase.",
	]
	_show_overlay("Drop rates", "\n".join(lines), "Close", "", Callable())


func _on_privacy() -> void:
	_show_overlay("Privacy policy",
			"A full privacy policy will be published before launch. The game collects only what is needed to run your account: an anonymous id, your cards, and your gem balance.",
			"Close", "", Callable())


func _on_terms() -> void:
	_show_overlay("Terms of service",
			"Terms of service will be published before launch. In-app purchases and odds are described in the shop and on the pull screen.",
			"Close", "", Callable())


func _toast(message: String) -> void:
	_show_overlay(message, "", "OK", "", Callable())


# --- overlay ------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(Tokens.color(&"bg"), 0.82)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(scrim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(centre)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	panel.add_theme_stylebox_override("panel", Surfaces.panel(2))
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", Tokens.space(&"s16"))
	panel.add_child(col)

	_overlay_title = Label.new()
	_overlay_title.name = "Title"
	_overlay_title.theme_type_variation = "Title"
	_overlay_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_overlay_title)

	_overlay_body = Label.new()
	_overlay_body.name = "Body"
	_overlay_body.theme_type_variation = "Body"
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_overlay_body)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", Tokens.space(&"s12"))
	buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(buttons)

	_overlay_cancel = Button.new()
	_overlay_cancel.name = "Cancel"
	_overlay_cancel.theme_type_variation = "ButtonSecondary"
	_overlay_cancel.custom_minimum_size = Vector2(0.0, MIN_ROW)
	_overlay_cancel.focus_mode = Control.FOCUS_ALL
	_overlay_cancel.add_theme_stylebox_override("focus", _focus_style())
	_overlay_cancel.pressed.connect(_on_overlay_cancel)
	_a11y(_overlay_cancel, "Cancel", "Dismiss this dialog")
	buttons.add_child(_overlay_cancel)
	_controls.append(_overlay_cancel)

	_overlay_confirm = Button.new()
	_overlay_confirm.name = "Confirm"
	_overlay_confirm.custom_minimum_size = Vector2(0.0, MIN_ROW)
	_overlay_confirm.focus_mode = Control.FOCUS_ALL
	_overlay_confirm.add_theme_stylebox_override("focus", _focus_style())
	_overlay_confirm.pressed.connect(_on_overlay_confirm)
	_a11y(_overlay_confirm, "Confirm", "Accept this dialog")
	buttons.add_child(_overlay_confirm)
	_controls.append(_overlay_confirm)


func _show_overlay(title: String, body: String, confirm_text: String,
		cancel_text: String, cb: Callable) -> void:
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay_body.visible = not body.is_empty()
	_overlay_confirm.text = confirm_text
	_overlay_confirm.visible = not confirm_text.is_empty()
	_overlay_cancel.text = cancel_text
	_overlay_cancel.visible = not cancel_text.is_empty()
	_overlay_cb = cb
	_overlay.visible = true
	_overlay.move_to_front()


func _hide_overlay() -> void:
	_overlay.visible = false
	_overlay_cb = Callable()


func _on_overlay_confirm() -> void:
	if _overlay_cb.is_valid():
		_overlay_cb.call()
	else:
		_hide_overlay()


func _on_overlay_cancel() -> void:
	if delete_stage == 1 or delete_stage == 2:
		cancel_delete()
		return
	if sign_out_stage == 1:
		sign_out_stage = 0
	_hide_overlay()


# --- settings plumbing --------------------------------------------------------

func _settings_node() -> Node:
	if settings != null:
		return settings
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings")


func _game_state() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _supabase() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Supabase")


func _setting_value(key: String) -> Variant:
	var s := _settings_node()
	if s != null:
		return s.get(key)
	return SettingsScript.DEFAULTS.get(key)


func _write_setting(key: String, value: Variant) -> void:
	var s := _settings_node()
	if s != null:
		s.set(key, value)


func _current_option_value(key: String) -> String:
	var s := _settings_node()
	if key == "text_size":
		return str(s.text_size_name()) if s != null else "default"
	return str(_setting_value(key))


func _on_setting_changed(key: String) -> void:
	# Keep the widgets in step when another lane flips a setting.
	if _state_labels.has(key):
		var on := bool(_setting_value(key))
		_state_labels[key].text = "On" if on else "Off"
	if _option_nodes.has(key):
		var values: Array = SettingsScript.TILT_MODES if key == "card_tilt_mode" \
				else SettingsScript.TEXT_SIZE_ORDER
		var current := _current_option_value(key)
		var idx := values.find(current)
		if idx >= 0:
			(_option_nodes[key] as OptionButton).select(idx)


# --- info rows ----------------------------------------------------------------

func _refresh_info_rows() -> void:
	if _value_labels.is_empty():
		return
	var anon := bool(_home.get("is_anonymous", true))
	_set_value("guest", "Guest account" if anon else "Signed in")
	var id := _player_id
	if id.is_empty():
		var sb := _supabase()
		id = str(sb.get("user_id")) if sb != null else ""
	_set_value("player_id", id if not id.is_empty() else "Not available yet")
	_set_value("lifetime", FormatScript.cents_to_text(int(_home.get("total_spent_cents", 0))))
	_set_value("credits",
			"Fonts: Unbounded and Manrope (SIL Open Font License). Art and code by the studio.")
	_set_value("version", _version())


func _set_value(name: String, text: String) -> void:
	if _value_labels.has(name) and _value_labels[name] is Label:
		(_value_labels[name] as Label).text = text


func _version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", APP_VERSION_FALLBACK))
	return v if not v.is_empty() else APP_VERSION_FALLBACK


func _first_banner() -> Dictionary:
	if _banners.is_empty():
		return {}
	var b: Variant = _banners[0]
	return b if b is Dictionary else {}


# --- helpers ------------------------------------------------------------------

func _a11y(control: Control, a_name: String, a_desc: String) -> void:
	control.set("accessibility_name", a_name)
	if not a_desc.is_empty():
		control.set("accessibility_description", a_desc)


func _focus_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Tokens.color(&"surface_2"), 0.0)
	sb.border_color = Tokens.color(&"accent_secondary")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(Tokens.radius(&"small"))
	sb.draw_center = false
	return sb


func _format_percent(value: float) -> String:
	return "%d%%" % int(round(value))


func _format_sensitivity(value: float) -> String:
	return "%d%%" % int(round(value))


# --- scrolling for screenshots ------------------------------------------------

func _scroll_to(value: int) -> void:
	_scroll_target = value
	set_process(true)


func _process(_delta: float) -> void:
	if _scroll_target < 0 or _scroll == null:
		return
	_scroll.scroll_vertical = _scroll_target


# --- screenshots --------------------------------------------------------------

func screenshot_count() -> int:
	return 4


func screenshot_setup(i: int) -> String:
	_ensure_built()
	_screenshot_mode = true
	set_preview_data(_demo_home(), _demo_banners(), "8f3c1a52-9d4e-4b21-a7c0-6e2d5b8f1043")
	match i:
		0:
			_scroll_to(0)
			return "settings_top"
		1:
			_scroll_to(720)
			return "settings_middle"
		2:
			_scroll_to(1000000)
			return "settings_bottom"
		_:
			_scroll_to(1000000)
			request_delete()
			return "settings_delete_confirm"


static func _demo_home() -> Dictionary:
	return {
		"gems": 1600,
		"pity": {"since_epic": 8, "since_legendary": 75, "total_pulls": 40},
		"streak": {"current": 5, "best": 7, "freezes": 1, "claimed_today": false},
		"total_spent_cents": 1999,
		"alpha_mode": false,
		"is_anonymous": true,
	}


static func _demo_banners() -> Array:
	return [{
		"id": "standard",
		"name": "Standard",
		"cost_single": 160,
		"cost_ten": 1600,
		"odds": {"common": 0.70, "rare": 0.20, "epic": 0.08, "legendary": 0.02},
		"pity": {"epic_every": 10, "legendary_at": 80},
		"holo_odds": {"none": 0.85, "silver": 0.08, "rainbow": 0.04,
			"gold": 0.02, "prism": 0.008, "galaxy": 0.002},
	}]
