extends Control
## Home tab (T-006): the daily claim strip and the pack panel. The pack is the
## hero and every other control is quiet; the odds + pity row is always on
## screen because Google Play requires odds before purchase (AGENTS.md).
##
## Grey-box on purpose: approved Figma designs replace the layout later, so all
## view code lives in _build_* and all state in GameState. Tests and the
## screenshot harness inject data with set_preview_data(), which never touches
## the network (builder rule).

const MIN_TAP_DP := 48.0
const REWARD_HOLD_SECONDS := 2.0
const ALPHA_BUTTON_TEXT := "+1600 gems (alpha)"

## True after set_preview_data, so _ready never fires a real request in tests
## or screenshots.
var _preview_mode := false
var _home: Dictionary = {}
var _banners: Array = []
var _banner_index := 0
var _pulling := false

var _built := false
var _faucet_row: HBoxContainer
var _faucet_button: Button
var _streak_label: Label
var _reward_label: Label
var _claim_button: Button
var _prev_button: Button
var _next_button: Button
var _banner_label: Label
var _pack_label: Label
var _open_single: Button
var _open_ten: Button
var _hint_label: Label
var _error_label: Label
var _result_label: Label
var _info_row: VBoxContainer
var _odds_label: Label
var _pity_label: Label
var _holo_toggle: Button
var _holo_label: Label

## Injectable Settings (tests); null means the autoload.
var settings: Node = null
var _pending_count := 0
var _confirm_overlay: Control
var _confirm_label: Label


func _ready() -> void:
	_ensure_built()
	# Deferred so the screenshot harness can set preview data first (same trick
	# as app_shell: never hit the network under screenshot.gd).
	call_deferred("_begin")


# --- state injection --------------------------------------------------------

## Offline entry point for tests and screenshots. _preview_mode also disables
## the claim/faucet/pull handlers, so a stray press cannot reach the network.
func set_preview_data(home: Dictionary, banners: Array) -> void:
	_ensure_built()
	_preview_mode = true
	_set_data(home, banners)


func _set_data(home: Dictionary, banners: Array) -> void:
	_home = (home as Dictionary).duplicate(true) if home is Dictionary else {}
	_banners = (banners as Array).duplicate(true) if banners is Array else []
	_banner_index = clampi(_banner_index, 0, maxi(_banners.size() - 1, 0))
	_refresh_alpha()
	_refresh_daily()
	_refresh_pack()
	_refresh_info()


func _state_node() -> Node:
	# Tests build the tab detached; absolute /root lookups error there.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _begin() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	if not gs.home_changed.is_connected(_on_state_changed):
		gs.home_changed.connect(_on_state_changed)
	if not gs.banners_changed.is_connected(_on_state_changed):
		gs.banners_changed.connect(_on_state_changed)
	_on_state_changed()
	await gs.refresh_banners()
	_on_state_changed()


func _on_state_changed() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	_set_data(gs.get("home"), gs.get("banners"))


# --- daily claim ------------------------------------------------------------

func _on_claim_pressed() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	_claim_button.disabled = true
	var res: Dictionary = await gs.claim_daily()
	if not bool(res.get("ok", false)):
		_show_error(str(res.get("error", "Daily claim failed.")))
		_refresh_daily()
		return
	var data: Dictionary = res.get("data", {})
	_reward_label.text = "+%d gems" % int(data.get("reward", 0))
	_reward_label.visible = true
	# Reconcile the cache with what the server just granted, before the refresh.
	var streak: Dictionary = _home.get("streak", {})
	streak["claimed_today"] = true
	_home["streak"] = streak
	if data.has("gems"):
		_home["gems"] = int(data.get("gems", 0))
	_refresh_daily()
	# Hold the reward on screen for two seconds, then pull the truth.
	await get_tree().create_timer(REWARD_HOLD_SECONDS).timeout
	_reward_label.visible = false
	await gs.refresh_home()
	_refresh_daily()


func _refresh_daily() -> void:
	if _streak_label == null:
		return
	var streak: Dictionary = _home.get("streak", {})
	_streak_label.text = "Streak: %d days · Freezes: %d" % [
		int(streak.get("current", 0)), int(streak.get("freezes", 0)),
	]
	var claimed := bool(streak.get("claimed_today", false))
	_claim_button.disabled = claimed
	_claim_button.text = "Claimed - come back tomorrow" if claimed else "Claim"


# --- pack panel -------------------------------------------------------------

func _current_banner() -> Dictionary:
	if _banner_index < 0 or _banner_index >= _banners.size():
		return {}
	var b: Variant = _banners[_banner_index]
	return b if b is Dictionary else {}


func _refresh_pack() -> void:
	if _open_single == null:
		return
	var several := _banners.size() > 1
	_prev_button.visible = several
	_next_button.visible = several
	if _banners.is_empty():
		_banner_label.text = "No banner"
		_pack_label.text = "No banner"
		_open_single.disabled = true
		_open_ten.disabled = true
		_set_hint("No banner available.")
		return
	var b := _current_banner()
	_banner_label.text = str(b.get("name", ""))
	_pack_label.text = str(b.get("name", ""))
	var gems := int(_home.get("gems", 0))
	var single := int(b.get("cost_single", 0))
	var ten := int(b.get("cost_ten", 0))
	_open_single.text = "Open 1 - %d gems" % single
	_open_ten.text = "Open 10 - %d gems" % ten
	_open_single.disabled = _pulling or gems < single
	_open_ten.disabled = _pulling or gems < ten
	_open_single.tooltip_text = _shortfall("Open 1", single, gems)
	_open_ten.tooltip_text = _shortfall("Open 10", ten, gems)
	if _pulling:
		_set_hint("")
	elif gems < single:
		_set_hint("Not enough gems: need %d, have %d." % [single, gems])
	elif gems < ten:
		_set_hint("Open 10 needs %d gems, have %d." % [ten, gems])
	else:
		_set_hint("")


## Why a disabled button is disabled; empty when the button is affordable.
func _shortfall(_action: String, cost: int, gems: int) -> String:
	if gems >= cost:
		return ""
	return "Not enough gems: %d needed, %d available." % [cost, gems]


func _set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()


func _cycle_banner(step: int) -> void:
	if _banners.size() <= 1:
		return
	_banner_index = wrapi(_banner_index + step, 0, _banners.size())
	_refresh_pack()
	_refresh_info()


## True when a pull that costs gems should ask first (D-003 setting, default
## ON). A free pull never prompts; no Settings node means no prompt either, so
## tests and screenshots keep the old one-tap flow.
static func needs_spend_confirm(settings: Node, cost: int) -> bool:
	if settings == null or cost <= 0:
		return false
	return bool(settings.get("confirm_spend_gems"))


func _settings_node() -> Node:
	if settings != null:
		return settings
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings")


func _on_open_pressed(count: int) -> void:
	if _preview_mode or _pulling:
		return
	var b := _current_banner()
	if b.is_empty():
		return
	var cost := int(b.get("cost_single", 0)) if count == 1 else int(b.get("cost_ten", 0))
	if needs_spend_confirm(_settings_node(), cost):
		_pending_count = count
		_show_spend_confirm(cost)
		return
	_start_pull(count)


func _start_pull(count: int) -> void:
	if _preview_mode or _pulling:
		return
	var b := _current_banner()
	if b.is_empty():
		return
	var gs := _state_node()
	if gs == null:
		return
	_pulling = true
	_result_label.visible = false
	_error_label.visible = false
	_refresh_pack()
	# T-007 will listen for the reveal; if nobody does yet, show the plain list.
	var has_listener: bool = gs.pull_finished.get_connections().size() > 0
	var res: Dictionary = await gs.pull(str(b.get("id", "")), count)
	_pulling = false
	_refresh_pack()
	if not bool(res.get("ok", false)):
		_show_error(str(res.get("error", "Pull failed.")))
		return
	if not has_listener:
		_result_label.text = PackMath.cards_summary((res.get("data", {}) as Dictionary).get("cards", []))
		_result_label.visible = true
	await gs.refresh_home()
	_refresh_daily()
	_refresh_pack()


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true


# --- confirm before spending (D-003) -----------------------------------------

## The confirm the "Confirm before spending gems" setting turns on: one extra
## tap before a pull that costs gems, never before a free one.
func _show_spend_confirm(cost: int) -> void:
	if _confirm_overlay == null:
		_build_spend_confirm()
	_confirm_label.text = "Open for %d gems?" % cost
	_confirm_overlay.visible = true
	_confirm_overlay.move_to_front()


func _build_spend_confirm() -> void:
	_confirm_overlay = Control.new()
	_confirm_overlay.name = "SpendConfirm"
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var scrim := ColorRect.new()
	scrim.color = Color(Tokens.color(&"bg"), 0.82)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_overlay.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	panel.add_theme_stylebox_override("panel", Surfaces.panel(2))
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.space(&"s16"))
	panel.add_child(col)

	_confirm_label = Label.new()
	_confirm_label.name = "Message"
	_confirm_label.theme_type_variation = "Title"
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_confirm_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", Tokens.space(&"s12"))
	col.add_child(row)

	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.theme_type_variation = "ButtonSecondary"
	cancel.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	cancel.pressed.connect(func() -> void: _confirm_overlay.visible = false)
	row.add_child(cancel)

	var open := Button.new()
	open.name = "ConfirmOpen"
	open.text = "Open"
	open.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	open.pressed.connect(_on_spend_confirmed)
	row.add_child(open)


func _on_spend_confirmed() -> void:
	_confirm_overlay.visible = false
	_start_pull(_pending_count)


# --- always-visible info row ------------------------------------------------

func _refresh_info() -> void:
	if _odds_label == null:
		return
	if _banners.is_empty():
		_odds_label.text = "Odds unavailable."
		_pity_label.text = ""
		_holo_label.text = ""
		return
	var b := _current_banner()
	_odds_label.text = PackMath.rarity_odds_text(b.get("odds", {}))
	_pity_label.text = PackMath.pity_text(_home.get("pity", {}), b.get("pity", {}))
	_holo_label.text = PackMath.holo_odds_text(b.get("holo_odds", {}))


func _on_holo_toggled(pressed: bool) -> void:
	_holo_label.visible = pressed


# --- alpha faucet -----------------------------------------------------------

func _on_alpha_pressed() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	var res: Dictionary = await gs.alpha_grant_gems()
	if not bool(res.get("ok", false)):
		_show_error(str(res.get("error", "Grant failed.")))
		return
	await gs.refresh_home()
	_refresh_pack()


func _refresh_alpha() -> void:
	if _faucet_row == null:
		return
	_faucet_row.visible = bool(_home.get("alpha_mode", false))


# --- readouts (used by tests and future tasks) ------------------------------

func info_row() -> Control:
	_ensure_built()
	return _info_row


func odds_text() -> String:
	_ensure_built()
	return _odds_label.text


func odds_visible() -> bool:
	_ensure_built()
	return _odds_label.visible


func pity_text() -> String:
	_ensure_built()
	return _pity_label.text


func holo_label_visible() -> bool:
	_ensure_built()
	return _holo_label.visible


func open_buttons() -> Array[Button]:
	_ensure_built()
	return [_open_single, _open_ten]


func claim_button() -> Button:
	_ensure_built()
	return _claim_button


func faucet_button() -> Button:
	_ensure_built()
	return _faucet_button


func faucet_visible() -> bool:
	_ensure_built()
	return _faucet_row.visible


func prev_button() -> Button:
	_ensure_built()
	return _prev_button


func next_button() -> Button:
	_ensure_built()
	return _next_button


func holo_toggle() -> Button:
	_ensure_built()
	return _holo_toggle


func banner_name_text() -> String:
	_ensure_built()
	return _banner_label.text


# --- construction -----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_build_faucet(col)
	_build_daily(col)
	_build_pack(col)
	_build_info(col)

	_refresh_alpha()
	_refresh_daily()
	_refresh_pack()
	_refresh_info()


func _build_faucet(parent: Control) -> void:
	_faucet_row = HBoxContainer.new()
	_faucet_row.name = "FaucetRow"
	_faucet_row.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(_faucet_row)

	_faucet_button = Button.new()
	_faucet_button.name = "AlphaFaucet"
	_faucet_button.text = ALPHA_BUTTON_TEXT
	_faucet_button.flat = true
	_faucet_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_faucet_button.pressed.connect(_on_alpha_pressed)
	_faucet_row.add_child(_faucet_button)


func _build_daily(parent: Control) -> void:
	var strip := PanelContainer.new()
	strip.name = "DailyStrip"
	parent.add_child(strip)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	strip.add_child(row)

	_streak_label = Label.new()
	_streak_label.name = "StreakLabel"
	_streak_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_streak_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_streak_label)

	_reward_label = Label.new()
	_reward_label.name = "RewardLabel"
	_reward_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reward_label.visible = false
	row.add_child(_reward_label)

	_claim_button = Button.new()
	_claim_button.name = "ClaimButton"
	_claim_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_claim_button.pressed.connect(_on_claim_pressed)
	row.add_child(_claim_button)


func _build_pack(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "PackPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var banner_row := HBoxContainer.new()
	banner_row.name = "BannerRow"
	col.add_child(banner_row)

	_prev_button = Button.new()
	_prev_button.name = "PrevBanner"
	_prev_button.text = "<"
	_prev_button.custom_minimum_size = Vector2(MIN_TAP_DP, MIN_TAP_DP)
	_prev_button.pressed.connect(_cycle_banner.bind(-1))
	banner_row.add_child(_prev_button)

	_banner_label = Label.new()
	_banner_label.name = "BannerName"
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_row.add_child(_banner_label)

	_next_button = Button.new()
	_next_button.name = "NextBanner"
	_next_button.text = ">"
	_next_button.custom_minimum_size = Vector2(MIN_TAP_DP, MIN_TAP_DP)
	_next_button.pressed.connect(_cycle_banner.bind(1))
	banner_row.add_child(_next_button)

	# Pack art placeholder: a plain panel with the banner name, no logos. The
	# art pipeline owns real art; nothing here generates or downloads any.
	var art := PanelContainer.new()
	art.name = "PackArt"
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size = Vector2(0.0, 320.0)
	col.add_child(art)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	art.add_child(centre)

	_pack_label = Label.new()
	_pack_label.name = "PackName"
	_pack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Without a min width the centered label collapses and wraps mid-word; the
	# art panel is far wider than this, so it only affects the placeholder text.
	_pack_label.custom_minimum_size = Vector2(240.0, 0.0)
	centre.add_child(_pack_label)

	# The two CTAs sit after the art, i.e. in the bottom third of the panel.
	var buttons := HBoxContainer.new()
	buttons.name = "OpenButtons"
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)

	_open_single = Button.new()
	_open_single.name = "OpenSingle"
	_open_single.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_single.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_open_single.pressed.connect(_on_open_pressed.bind(1))
	buttons.add_child(_open_single)

	_open_ten = Button.new()
	_open_ten.name = "OpenTen"
	_open_ten.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_ten.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_open_ten.pressed.connect(_on_open_pressed.bind(10))
	buttons.add_child(_open_ten)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.visible = false
	col.add_child(_hint_label)

	_error_label = Label.new()
	_error_label.name = "Error"
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	col.add_child(_error_label)

	_result_label = Label.new()
	_result_label.name = "Result"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.visible = false
	col.add_child(_result_label)


func _build_info(parent: Control) -> void:
	_info_row = VBoxContainer.new()
	_info_row.name = "InfoRow"
	_info_row.add_theme_constant_override("separation", 4)
	parent.add_child(_info_row)

	# Always visible, never behind a toggle: Play requires odds up front.
	_odds_label = Label.new()
	_odds_label.name = "Odds"
	_odds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_row.add_child(_odds_label)

	_pity_label = Label.new()
	_pity_label.name = "Pity"
	_pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_row.add_child(_pity_label)

	_holo_toggle = Button.new()
	_holo_toggle.name = "HoloToggle"
	_holo_toggle.text = "Holo odds"
	_holo_toggle.flat = true
	_holo_toggle.toggle_mode = true
	_holo_toggle.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_holo_toggle.toggled.connect(_on_holo_toggled)
	_info_row.add_child(_holo_toggle)

	_holo_label = Label.new()
	_holo_label.name = "HoloOdds"
	_holo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_holo_label.visible = false
	_info_row.add_child(_holo_label)


# --- screenshots ------------------------------------------------------------

func screenshot_count() -> int:
	return 2


func screenshot_setup(i: int) -> String:
	_ensure_built()
	match i:
		0:
			set_preview_data(_demo_home(1600, false, false), _demo_banners())
			return "ready"
		_:
			set_preview_data(_demo_home(40, true, true), _demo_banners())
			return "poor_claimed_alpha"


func _demo_home(gems: int, claimed: bool, alpha: bool) -> Dictionary:
	return {
		"gems": gems,
		"pity": {"since_epic": 8, "since_legendary": 75, "total_pulls": 40},
		"streak": {"current": 5, "best": 7, "freezes": 1, "claimed_today": claimed},
		"alpha_mode": alpha,
	}


func _demo_banners() -> Array:
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
