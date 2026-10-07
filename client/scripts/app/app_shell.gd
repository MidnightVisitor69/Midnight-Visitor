extends Control
## App shell (T-005, grey-box): the frame every screen plugs into. It signs in
## anonymously on first run, shows the one currency (Gems) in a slim top bar,
## and switches between the tabs. Plain Godot controls on purpose: approved
## Figma designs replace this later (AGENTS.md UI rules), so layout stays in
## _build_* and game state stays in GameState.

const HoloTestPath := "res://scenes/dev/holo_test.tscn"
## Read the flag from the script so the shell builds in tests without autoloads.
const ConfigScript := preload("res://scripts/config.gd")

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


func _state_node() -> Node:
	# Tests build the shell detached from the tree; absolute /root lookups error there.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _open_holo_test() -> void:
	if get_tree() != null:
		get_tree().change_scene_to_file(HoloTestPath)


# --- readouts (used by tests) -----------------------------------------------

## Every bottom-bar tab button, in draw order.
func tab_buttons() -> Array[Button]:
	_ensure_built()
	return _tab_buttons


## The tab ids the shell actually built.
func tab_ids() -> PackedStringArray:
	_ensure_built()
	return _tab_ids


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


func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.anchor_right = 1.0
	_top_bar.offset_bottom = TOP_BAR_HEIGHT
	add_child(_top_bar)

	var row := HBoxContainer.new()
	row.name = "Row"
	_top_bar.add_child(row)

	var title := Label.new()
	title.text = "Waifu Card Collector"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)

	_gem_label = Label.new()
	_gem_label.name = "Gems"
	_gem_label.text = "Gems: --"
	_gem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_gem_label)

	# The holo bench never ships enabled, but devs need it reachable.
	if is_debug:
		var holo := Button.new()
		holo.name = "HoloTestButton"
		holo.text = "Holo test"
		holo.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
		holo.pressed.connect(_open_holo_test)
		row.add_child(holo)


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
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select_tab.bind(id))
		row.add_child(b)
		_tab_buttons.append(b)


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
	_retry_button.visible = false
	_retry_button.pressed.connect(_begin_sign_in)
	col.add_child(_retry_button)


# --- state to view ----------------------------------------------------------

func _select_tab(id: String) -> void:
	active_tab = id
	for tid in _tab_pages:
		(_tab_pages[tid] as Control).visible = (tid == id)
	for b in _tab_buttons:
		b.button_pressed = b.name == "Tab_" + id


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
