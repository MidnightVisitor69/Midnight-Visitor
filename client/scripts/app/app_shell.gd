extends Control
## App shell (T-005, grey-box): the frame every screen plugs into. It signs in
## anonymously on first run, shows the one currency (Gems) in a slim top bar,
## and switches between the tabs. Plain Godot controls on purpose: approved
## Figma designs replace this later (AGENTS.md UI rules), so layout stays in
## _build_* and game state stays in GameState.

const HoloTestPath := "res://scenes/dev/holo_test.tscn"
## Read the flag from the script so the shell builds in tests without autoloads.
const ConfigScript := preload("res://scripts/config.gd")
## The Settings screen (D-003) opens over the shell as a full-screen overlay.
const SettingsScreenScene := preload("res://scenes/app/settings_screen.tscn")

const TAB_HOME := "home"
const TAB_COLLECTION := "collection"
const TAB_TRADE := "trade"
const TAB_SHOP := "shop"

## Android's minimum tap target; the tab bar lives in the thumb zone.
const MIN_TAP_DP := 48.0
const TOP_BAR_HEIGHT := 56.0
const TAB_BAR_HEIGHT := 64.0

const TAB_TITLES := {
	TAB_HOME: "Home",
	TAB_COLLECTION: "Collection",
	TAB_TRADE: "Trade",
	TAB_SHOP: "Shop",
}
const TAB_SCENES := {
	TAB_HOME: "res://scenes/app/tabs/home_tab.tscn",
	TAB_COLLECTION: "res://scenes/app/tabs/collection_tab.tscn",
	TAB_TRADE: "res://scenes/app/tabs/trade_tab.tscn",
	TAB_SHOP: "res://scenes/app/tabs/shop_tab.tscn",
}

## Tabs on screen. Shop stays hidden until the dev turns it on (AGENTS.md).
static func visible_tab_ids(shop_enabled: bool) -> PackedStringArray:
	var ids := PackedStringArray([TAB_HOME, TAB_COLLECTION, TAB_TRADE])
	if shop_enabled:
		ids.append(TAB_SHOP)
	return ids


## "signing_in" | "ready" | "error". Read by the status overlay.
var status := "signing_in"
var error_message := ""
var active_tab := TAB_HOME

## Whether this build may show dev-only affordances (the holo bench shortcut).
## The engine is sampled once here so the visibility decision is a plain bool
## that tests can pass in both ways instead of depending on how they were built.
var is_debug := OS.is_debug_build()

var _built := false
## Set by screenshot_setup so the harness never fires a real sign-in request.
var _screenshot_mode := false
var _tab_ids := PackedStringArray()
var _tab_buttons: Array[Button] = []
var _tab_pages: Dictionary = {}

var _top_bar: PanelContainer
var _content: Control
var _tab_bar: PanelContainer
var _overlay: CenterContainer
var _gem_label: Label
var _status_label: Label
var _retry_button: Button
var _title_label: Label
var _top_row: HBoxContainer
var _gear_button: Button
var _holo_button: Button
var _settings_screen: Control

## Injectable Settings for tests; null means the autoload.
var settings: Node = null


func _ready() -> void:
	_ensure_built()
	# Deferred so the screenshot harness can cancel the first request.
	call_deferred("_begin_session")


# --- session ----------------------------------------------------------------

func _begin_session() -> void:
	if _screenshot_mode:
		return
	var sb := get_node_or_null("/root/Supabase")
	if sb == null:
		_set_status("error", "Backend unavailable.")
		return
	if sb.is_signed_in():
		_after_sign_in()
	else:
		_begin_sign_in()


func _begin_sign_in() -> void:
	_set_status("signing_in", "")
	var sb := get_node_or_null("/root/Supabase")
	if sb == null:
		_set_status("error", "Backend unavailable.")
		return
	sb.sign_in_anonymously()


func _after_sign_in() -> void:
	var gs := _state_node()
	if gs == null:
		_set_status("error", "Backend unavailable.")
		return
	var ok: bool = await gs.refresh_home()
	if ok:
		_set_status("ready", "")
	else:
		_set_status("error", "Could not load your account. Tap Retry.")


func _on_signed_in() -> void:
	_after_sign_in()


func _on_auth_failed(message: String) -> void:
	_set_status("error", message)


func _on_signed_out() -> void:
	_set_status("error", "Session ended. Tap Retry.")


func _connect_autoloads() -> void:
	var sb := get_node_or_null("/root/Supabase")
	if sb != null:
		sb.signed_in.connect(_on_signed_in)
		sb.auth_failed.connect(_on_auth_failed)
		sb.signed_out.connect(_on_signed_out)
	var gs := _state_node()
	if gs != null and not gs.home_changed.is_connected(_update_gems):
		gs.home_changed.connect(_update_gems)
	var s := _settings_node()
	if s != null and not s.changed.is_connected(_on_setting_changed):
		s.changed.connect(_on_setting_changed)


func _state_node() -> Node:
	# Tests build the shell detached from the tree; absolute /root lookups error there.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _open_holo_test() -> void:
	if get_tree() != null:
		get_tree().change_scene_to_file(HoloTestPath)


# --- settings ---------------------------------------------------------------

## Open Settings as a full-screen overlay; the tab bar and top bar stay behind
## it, so the player never loses their place.
func _open_settings() -> void:
	if _settings_screen != null and is_instance_valid(_settings_screen):
		_settings_screen.visible = true
		_settings_screen.move_to_front()
		return
	_settings_screen = SettingsScreenScene.instantiate() as Control
	_settings_screen.name = "SettingsScreen"
	_settings_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_screen.closed.connect(_on_settings_closed)
	add_child(_settings_screen)
	_settings_screen.move_to_front()


func _on_settings_closed() -> void:
	if _settings_screen != null and is_instance_valid(_settings_screen):
		_settings_screen.visible = false


func _settings_node() -> Node:
	if settings != null:
		return settings
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings")


func _left_handed() -> bool:
	var s := _settings_node()
	return bool(s.get("left_handed_layout")) if s != null else false


## Left-handed layout mirrors the floating secondary controls to the other side
## of the top bar (task). The title and the gem count stay put; only the
## controls a thumb reaches for move.
func _apply_left_handed() -> void:
	if _top_row == null or _gear_button == null:
		return
	var n := _top_row.get_child_count()
	if _left_handed():
		_top_row.move_child(_gear_button, 0)
		if _holo_button != null:
			_top_row.move_child(_holo_button, 1)
	else:
		_top_row.move_child(_gear_button, n - 1)
		if _holo_button != null:
			_top_row.move_child(_holo_button, n - 2)


func _on_setting_changed(key: String) -> void:
	if key == "left_handed_layout":
		_apply_left_handed()


# --- readouts (used by tests) -----------------------------------------------

## Every bottom-bar tab button, in draw order.
func tab_buttons() -> Array[Button]:
	_ensure_built()
	return _tab_buttons


## The tab ids the shell actually built.
func tab_ids() -> PackedStringArray:
	_ensure_built()
	return _tab_ids


func gear_button() -> Button:
	_ensure_built()
	return _gear_button


## The shell's OWN interactive controls, for the accessibility check. The tab
## pages are other lanes' screens and carry their own names.
func shell_controls() -> Array[Control]:
	_ensure_built()
	var out: Array[Control] = []
	for b in _tab_buttons:
		out.append(b)
	out.append(_gear_button)
	out.append(_retry_button)
	if _holo_button != null:
		out.append(_holo_button)
	return out


# --- accessibility helpers --------------------------------------------------

func _a11y(control: Control, a_name: String, a_desc := "") -> void:
	control.set("accessibility_name", a_name)
	if not a_desc.is_empty():
		control.set("accessibility_description", a_desc)


## The keyboard/controller focus ring: a 2-px cyan edge, never a glow.
func _focus_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Tokens.color(&"surface_2"), 0.0)
	sb.border_color = Tokens.color(&"accent_secondary")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(Tokens.radius(&"small"))
	sb.draw_center = false
	return sb


## The gear glyph: a hub plus eight teeth, 2-px stroke, drawn in code (no PNGs).
class GearIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 3.0
		var col := Tokens.color(&"text_secondary")
		draw_arc(c, r * 0.52, 0.0, TAU, 24, col, 2.0, true)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var inner := c + Vector2(cos(a), sin(a)) * r * 0.6
			var outer := c + Vector2(cos(a), sin(a)) * r
			draw_line(inner, outer, col, 2.0, true)


# --- construction -----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_top_bar()
	_build_content()
	_build_tab_bar()
	_build_overlay()
	_update_gems()
	_sync_status()
	if is_inside_tree():
		_connect_autoloads()
	_apply_left_handed()


func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.anchor_right = 1.0
	_top_bar.offset_bottom = TOP_BAR_HEIGHT
	add_child(_top_bar)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", Tokens.space(&"s8"))
	_top_bar.add_child(row)
	_top_row = row

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Waifu Card Collector"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title_label)

	_gem_label = Label.new()
	_gem_label.name = "Gems"
	_gem_label.text = "Gems: --"
	_gem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_gem_label)

	# The holo bench never ships enabled, but devs need it reachable.
	if is_debug:
		_holo_button = Button.new()
		_holo_button.name = "HoloTestButton"
		_holo_button.text = "Holo test"
		_holo_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
		_holo_button.focus_mode = Control.FOCUS_ALL
		_holo_button.add_theme_stylebox_override("focus", _focus_style())
		_holo_button.pressed.connect(_open_holo_test)
		_a11y(_holo_button, "Holo test bench", "Open the developer holo test scene")
		row.add_child(_holo_button)

	# The gear lives in the top bar (task) and opens Settings as an overlay.
	_gear_button = Button.new()
	_gear_button.name = "GearButton"
	_gear_button.custom_minimum_size = Vector2(MIN_TAP_DP, MIN_TAP_DP)
	_gear_button.focus_mode = Control.FOCUS_ALL
	_gear_button.add_theme_stylebox_override("focus", _focus_style())
	_gear_button.tooltip_text = "Settings"
	_gear_button.pressed.connect(_open_settings)
	_a11y(_gear_button, "Settings", "Open the settings screen")
	var icon := GearIcon.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_button.add_child(icon)
	row.add_child(_gear_button)

	_apply_left_handed()


func _build_content() -> void:
	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_top = TOP_BAR_HEIGHT
	_content.offset_bottom = -TAB_BAR_HEIGHT
	add_child(_content)

	for id in visible_tab_ids(ConfigScript.SHOP_ENABLED):
		var packed := load(TAB_SCENES[id]) as PackedScene
		if packed == null:
			continue
		var page := packed.instantiate() as Control
		page.name = "Page_" + id
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.add_child(page)
		_tab_pages[id] = page
	_select_tab(active_tab)


func _build_tab_bar() -> void:
	_tab_bar = PanelContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.anchor_top = 1.0
	_tab_bar.anchor_right = 1.0
	_tab_bar.anchor_bottom = 1.0
	_tab_bar.offset_top = -TAB_BAR_HEIGHT
	add_child(_tab_bar)

	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("separation", 0)
	_tab_bar.add_child(row)

	_tab_ids = visible_tab_ids(ConfigScript.SHOP_ENABLED)
	for id in _tab_ids:
		var b := Button.new()
		b.name = "Tab_" + id
		b.text = TAB_TITLES[id]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_button_style(b)
		b.pressed.connect(_select_tab.bind(id))
		_a11y(b, TAB_TITLES[id], "Switch to the %s tab" % TAB_TITLES[id])
		row.add_child(b)
		_tab_buttons.append(b)


## Quiet tabs: only the ACTIVE tab gets the thin neon bar (D-001's TabBar
## intent, applied to these buttons). Filled buttons on every tab made the whole
## bar read as active - neon is a precious resource (DESIGNER.md).
func _tab_button_style(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(Tokens.color(&"bg"), 0.0)
	normal.content_margin_top = Tokens.space(&"s12")
	normal.content_margin_bottom = Tokens.space(&"s12")
	var selected: StyleBoxFlat = normal.duplicate()
	selected.bg_color = Tokens.color(&"surface_1")
	selected.border_color = Tokens.color(&"accent")
	selected.border_width_bottom = 3
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", selected)
	# A real focus ring, not StyleBoxEmpty: keyboard/controller users must be
	# able to see which tab has focus (D-003 accessibility plumbing).
	b.add_theme_stylebox_override("focus", _focus_style())
	b.add_theme_color_override("font_color", Tokens.color(&"text_secondary"))
	b.add_theme_color_override("font_hover_color", Tokens.color(&"text_primary"))
	b.add_theme_color_override("font_pressed_color", Tokens.color(&"text_primary"))
	b.add_theme_font_size_override("font_size", Tokens.font_size(&"label"))


func _build_overlay() -> void:
	_overlay = CenterContainer.new()
	_overlay.name = "StatusOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(col)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status_label)

	_retry_button = Button.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = "Retry"
	_retry_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_retry_button.focus_mode = Control.FOCUS_ALL
	_retry_button.add_theme_stylebox_override("focus", _focus_style())
	_retry_button.visible = false
	_retry_button.pressed.connect(_begin_sign_in)
	_a11y(_retry_button, "Retry", "Try loading your account again")
	col.add_child(_retry_button)


# --- state to view ----------------------------------------------------------

func _select_tab(id: String) -> void:
	active_tab = id
	for tid in _tab_pages:
		(_tab_pages[tid] as Control).visible = (tid == id)
	for b in _tab_buttons:
		var on := b.name == "Tab_" + id
		b.button_pressed = on
		# Weight change marks the active tab without a second colour.
		b.add_theme_font_override("font", Tokens.ui_font(700 if on else 500))


func _set_status(state: String, message: String) -> void:
	status = state
	error_message = message
	_sync_status()


func _sync_status() -> void:
	if _overlay == null:
		return
	var ready := status == "ready"
	_top_bar.visible = ready
	_content.visible = ready
	_tab_bar.visible = ready
	_overlay.visible = not ready
	if status == "error":
		_status_label.text = error_message
		_retry_button.visible = true
	else:
		_status_label.text = "Signing in..."
		_retry_button.visible = false


func _update_gems() -> void:
	if _gem_label == null:
		return
	var amount: Variant = null
	var gs := _state_node()
	if gs != null:
		amount = (gs.get("home") as Dictionary).get("gems")
	_gem_label.text = "Gems: --" if amount == null else "Gems: %d" % int(amount)


# --- screenshots ------------------------------------------------------------

func screenshot_count() -> int:
	return 1


func screenshot_setup(_i: int) -> String:
	# Stay offline; show the shell frame with no account data yet.
	_screenshot_mode = true
	_set_status("ready", "")
	return "app_shell"
