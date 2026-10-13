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
var _gem_counter: GemCounter
var _status_label: Label
var _retry_button: Button
var _title_label: Label
var _top_row: HBoxContainer
var _gear_button: Button
var _holo_button: Button
var _settings_screen: Control

## Injectable Settings for tests; null means the autoload.
var settings: Node = null
## Injectable Sfx for tests; null means the autoload.
var sfx: Node = null
## Injectable GameState for tests; null means the autoload.
var state_override: Node = null


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
	if state_override != null:
		return state_override
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


## Injectable Sfx for tests; null means the autoload (same lazy pattern as
## PackOpening: the shell also builds where no autoloads exist).
func _sfx() -> Node:
	if sfx != null:
		return sfx
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Sfx")


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


## The top-bar gem counter (tests read count() and drive set_count).
func gem_counter() -> GemCounter:
	_ensure_built()
	return _gem_counter


## Whether the Collection tab's notification dot is currently visible.
func collection_dot_visible() -> bool:
	_ensure_built()
	var dot := _collection_dot()
	return dot != null and dot.visible


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
		# Hub ring plus eight short teeth: reads as a gear, not a sun.
		draw_arc(c, r * 0.42, 0.0, TAU, 24, col, 2.0, true)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var inner := c + Vector2(cos(a), sin(a)) * r * 0.62
			var outer := c + Vector2(cos(a), sin(a)) * r
			draw_line(inner, outer, col, 3.0, true)


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
	_top_bar.add_theme_stylebox_override("panel", Surfaces.panel(1))
	add_child(_top_bar)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", Tokens.space(&"s12"))
	_top_bar.add_child(row)
	_top_row = row

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Waifu Card Collector"
	_title_label.theme_type_variation = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title_label)

	# The ONE currency display (AGENTS.md): the shared GemCounter component,
	# which tweens to every new value instead of jumping (M-004).
	_gem_counter = GemCounter.new()
	_gem_counter.name = "GemCounter"
	row.add_child(_gem_counter)

	# The holo bench never ships enabled, but devs need it reachable.
	if is_debug:
		_holo_button = Button.new()
		_holo_button.name = "HoloTestButton"
		_holo_button.text = "Holo test"
		_holo_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
		_holo_button.focus_mode = Control.FOCUS_ALL
		_holo_button.add_theme_stylebox_override("focus", _focus_style())
		_holo_button.button_down.connect(func(): Motion.press(_holo_button))
		_holo_button.pressed.connect(_open_holo_test)
		_a11y(_holo_button, "Holo test bench", "Open the developer holo test scene")
		row.add_child(_holo_button)

	# The gear lives in the top bar (task) and opens Settings as an overlay.
	_gear_button = Button.new()
	_gear_button.name = "GearButton"
	# Quiet: the gear is a secondary control, so it wears no neon edge.
	_gear_button.theme_type_variation = "ButtonGhost"
	_gear_button.custom_minimum_size = Vector2(MIN_TAP_DP, MIN_TAP_DP)
	_gear_button.focus_mode = Control.FOCUS_ALL
	_gear_button.add_theme_stylebox_override("focus", _focus_style())
	_gear_button.button_down.connect(func(): Motion.press(_gear_button))
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
	_tab_bar.add_theme_stylebox_override("panel", Surfaces.panel(2))
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
		b.button_down.connect(func(): Motion.press(b))
		b.pressed.connect(func() -> void:
			Sfx.play("tap")
			_select_tab.call(id))
		_a11y(b, TAB_TITLES[id], "Switch to the %s tab" % TAB_TITLES[id])
		row.add_child(b)
		_tab_buttons.append(b)
		if id == TAB_COLLECTION:
			# The one notification dot (AGENTS.md: max one per tab). Created
			# exactly once and only ever shown/hidden, so a second dot is
			# structurally impossible (M-004).
			var dot := ColorRect.new()
			dot.name = "NotificationDot"
			dot.color = Tokens.color(&"reward")
			dot.custom_minimum_size = Vector2(10, 10)
			dot.size = Vector2(10, 10)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			dot.offset_left = -14
			dot.offset_top = 4
			dot.offset_right = -4
			dot.offset_bottom = 14
			dot.visible = false
			b.add_child(dot)


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
	panel.custom_minimum_size = Vector2(Tokens.space(&"s40") * 7, 0.0)
	panel.add_theme_stylebox_override("panel", Surfaces.panel(2))
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", Tokens.space(&"s16"))
	panel.add_child(col)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.theme_type_variation = "Body"
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
	_retry_button.button_down.connect(func(): Motion.press(_retry_button))
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
	if id == TAB_COLLECTION:
		# Opening the Collection is what the dot was for; it clears (M-004).
		on_collection_tab_opened()


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
	if _gem_counter == null:
		return
	var amount: Variant = null
	var gs := _state_node()
	if gs != null:
		amount = (gs.get("home") as Dictionary).get("gems")
	# Every gem change tweens to the new value, never jumps (M-004): faucet,
	# ad reward, pack spend and claim refresh all land here via home_changed.
	_gem_counter.set_count(0 if amount == null else int(amount))


# --- acquire moments (M-004) ----------------------------------------------------

## Daily claim: the reward counts up into the top-bar gem counter over 600 ms
## while a few soft gem particles travel from the claim button to the
## counter, and the gems sound plays once. Called by the Home tab's claim
## handler with the server-confirmed reward and the button's global position.
func play_claim_animation(reward: int, claim_button_global_pos: Vector2) -> void:
	if _gem_counter == null:
		return
	_gem_counter.set_count(_gem_counter.count() + reward, Motion.CLAIM_COUNT_UP_MS)
	_spawn_claim_particles(claim_button_global_pos)
	var s := _sfx()
	if s != null and s.has_method("play"):
		s.call("play", "gems")


## A few soft gem diamonds from the claim button to the gem icon. Cheap by
## design: one tween per particle, no texture - the diamond is drawn, not an
## image (DESIGNER.md).
func _spawn_claim_particles(from_global: Vector2) -> void:
	if not is_inside_tree() or _gem_counter == null:
		return
	# The counter's gem icon is its first 28x28 child cell; its centre is
	# close enough to the counter's top-left + half an icon.
	var to := _gem_counter.get_global_position() + Vector2(14, 14)
	for i in Motion.CLAIM_PARTICLE_COUNT:
		var p := GemCounter.GemIcon.new()
		p.name = "ClaimParticle_%d" % i
		p.custom_minimum_size = Vector2(14, 14)
		p.size = Vector2(14, 14)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Slightly transparent, not a new colour: the token scan bans Color(
		# literals here, and the diamond's own fill is already the reward token.
		p.modulate.a = 0.9
		add_child(p)
		p.global_position = from_global + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		var tw := create_tween()
		if i > 0:
			tw.tween_interval(Motion.CLAIM_PARTICLE_MS * 0.04 * i)
		tw.tween_property(p, "global_position",
			to + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
			Motion.CLAIM_PARTICLE_MS / 1000.0
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(p.queue_free)


## Pack Done: the received cards shrink and fly to the Collection tab button
## in a quick stagger; on arrival the button bumps to 1.08, the acquire
## sound plays once (not per card), and the Collection's one notification
## dot appears until the tab is opened. `cards` are the pull's card
## dictionaries (tinted by rarity); `start_positions` are their global
## positions on the summary grid, parallel to `cards`.
func play_acquire_animation(cards: Array, start_positions: Array) -> void:
	var tab_button := _tab_button_for(TAB_COLLECTION)
	if tab_button == null or not is_inside_tree():
		return
	var total := mini(cards.size(), start_positions.size())
	if total == 0:
		return
	var target := tab_button.get_global_position() + tab_button.size * 0.5
	for i in total:
		var card: Dictionary = cards[i] if cards[i] is Dictionary else {}
		var flyer := ColorRect.new()
		flyer.name = "FlyingCard_%d" % i
		flyer.color = Tokens.rarity_color(str(card.get("rarity", "common")))
		flyer.color.a = 0.9
		flyer.custom_minimum_size = Vector2(48, 72)
		flyer.size = Vector2(48, 72)
		flyer.pivot_offset = Vector2(24, 36)
		flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flyer)
		flyer.global_position = (start_positions[i] as Vector2) - Vector2(24, 36)
		var tw := create_tween()
		if i > 0:
			tw.tween_interval(Motion.ACQUIRE_STAGGER_MS / 1000.0 * i)
		tw.tween_property(flyer, "global_position", target,
			Motion.ACQUIRE_FLY_MS / 1000.0
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(flyer, "scale", Vector2.ZERO,
			Motion.ACQUIRE_FLY_MS / 1000.0
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		if i == total - 1:
			# The last card to land is the arrival: one bump, one dot, one
			# sound per pack - never per card (M-004).
			tw.finished.connect(func() -> void: _arrive_collection(tab_button))


## The arrival (M-004): the tab button bumps to 1.08 and settles, the
## Collection's one notification dot appears, and the acquire sound plays -
## once per pack, because only the last card's flight calls this.
func _arrive_collection(tab_button: Button) -> void:
	_bump_collection_tab(tab_button)
	show_collection_dot()
	var s := _sfx()
	if s != null and s.has_method("play"):
		s.call("play", "acquire")


## The arrival bump: a quick 1.08 that settles back to 1.0.
func _bump_collection_tab(tab_button: Button) -> void:
	var tw := tab_button.create_tween()
	tw.tween_property(tab_button, "scale", Vector2.ONE * Motion.ACQUIRE_SCALE_BUMP,
		Motion.ACQUIRE_SCALE_BUMP_MS / 1000.0
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tab_button, "scale", Vector2.ONE,
		Motion.ACQUIRE_SCALE_BUMP_MS / 1000.0
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Show the Collection tab's notification dot. Idempotent: the dot node is
## created exactly once in _build_tab_bar, so showing it again cannot create
## a second dot (M-004; AGENTS.md: max one dot per tab).
func show_collection_dot() -> void:
	var dot := _collection_dot()
	if dot != null:
		dot.visible = true


## Opening the Collection tab clears its dot. Called from _select_tab.
func on_collection_tab_opened() -> void:
	var dot := _collection_dot()
	if dot != null:
		dot.visible = false


## The Collection tab's notification dot, or null when not built yet. The dot
## is created in code, so it has no owner: pass owned = false or it is never
## found and the dot silently never lights (caught by the M-004 tests).
func _collection_dot() -> Control:
	var b := _tab_button_for(TAB_COLLECTION)
	if b == null:
		return null
	return b.find_child("NotificationDot", false, false) as Control


## The tab button for a tab id, or null when the bar has no such tab.
func _tab_button_for(tab_id: String) -> Button:
	for b in _tab_buttons:
		if b.name == "Tab_" + tab_id:
			return b
	return null


# --- screenshots ------------------------------------------------------------

func screenshot_count() -> int:
	return 1


func screenshot_setup(_i: int) -> String:
	# Stay offline; show the shell frame with no account data yet.
	_screenshot_mode = true
	_set_status("ready", "")
	return "app_shell"
