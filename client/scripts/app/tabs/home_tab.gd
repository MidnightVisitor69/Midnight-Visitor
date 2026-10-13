extends Control
## Home tab (T-006): the daily claim strip and the pack panel. The pack is the
## hero and every other control is quiet; the odds + pity row is always on
## screen because Google Play requires odds before purchase (AGENTS.md).
##
## Grey-box on purpose: approved Figma designs replace the layout later, so all
## view code lives in _build_* and all state in GameState. Tests and the
## screenshot harness inject data with set_preview_data(), which never touches
## the network (builder rule).
##
## T-015: rewarded ad button (feature-flagged, hidden when ads_enabled=false).

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
## Ads (T-015)
var _ad_row: HBoxContainer
var _ad_button: Button
var _ad_label: Label

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
	_refresh_ad()
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

## The shared tap moment (M-004): one helper for every prototype button -
## the scale dip through Motion.press, then exactly one tap sound.
func _tap_feedback(button: BaseButton) -> void:
	Motion.press(button)
	Sfx.play("tap")


func _on_claim_pressed() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	_claim_button.disabled = true
	var res: Dictionary = await gs.claim_daily()
	if not bool(res.get("ok", false)):
		_show_error(str(res.get("error", "Daily claim failed")))
		_refresh_daily()
		return
	var data: Dictionary = res.get("data", {})
	_reward_label.text = "+%d gems" % int(data.get("reward", 0))
	_reward_label.visible = true
	# The reward counts up into the top-bar gem counter (600 ms), gem
	# particles travel from the claim button to it, gems sounds once.
	var shell := get_node_or_null("/root/AppShell")
	if shell != null and shell.has_method("play_claim_animation"):
		shell.call("play_claim_animation", int(data.get("reward", 0)),
			_claim_button.get_global_position() + _claim_button.size * 0.5)
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
	_streak_label.text = "%d day streak · %d freeze(s)" % [
		int(streak.get("current", 0)), int(streak.get("freezes", 0)),
	]
	var claimed := bool(streak.get("claimed_today", false))
	_claim_button.disabled = claimed
	_claim_button.text = "Claimed" if claimed else "Claim"


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
		_set_hint("No banner available")
		return
	var b := _current_banner()
	_banner_label.text = str(b.get("name", ""))
	_pack_label.text = str(b.get("name", ""))
	var gems := int(_home.get("gems", 0))
	var single := int(b.get("cost_single", 0))
	var ten := int(b.get("cost_ten", 0))
	_open_single.text = "Open 1 · %d gems" % single
	_open_ten.text = "Open 10 · %d gems" % ten
	_open_single.disabled = _pulling or gems < single
	_open_ten.disabled = _pulling or gems < ten
	_open_single.tooltip_text = _shortfall("Open 1", single, gems)
	_open_ten.tooltip_text = _shortfall("Open 10", ten, gems)
	if _pulling:
		_set_hint("")
	elif gems < single:
		_set_hint("Need %d gems, have %d" % [single, gems])
	elif gems < ten:
		_set_hint("Open 10 needs %d gems, have %d" % [ten, gems])
	else:
		_set_hint("")


## Why a disabled button is disabled; empty when the button is affordable.
func _shortfall(_action: String, cost: int, gems: int) -> String:
	if gems >= cost:
		return ""
	return "Need %d gems, have %d" % [cost, gems]


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
		_show_error(str(res.get("error", "Pull failed")))
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
	_error_label.add_theme_color_override("font_color", Tokens.color(&"danger"))


# --- confirm before spending (D-003) -----------------------------------------

## The confirm the "Confirm before spending gems" setting turns on: one extra
## tap before a pull that costs gems, never before a free one.
func _show_spend_confirm(cost: int) -> void:
	if _confirm_overlay == null:
		_build_spend_confirm()
	_confirm_label.text = "Spend %d gems?" % cost
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
	cancel.button_down.connect(func(): _tap_feedback(cancel))
	row.add_child(cancel)

	var open := Button.new()
	open.name = "ConfirmOpen"
	open.text = "Open"
	open.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	open.pressed.connect(_on_spend_confirmed)
	open.button_down.connect(func(): _tap_feedback(open))
	row.add_child(open)


func _on_spend_confirmed() -> void:
	_confirm_overlay.visible = false
	_start_pull(_pending_count)


# --- always-visible info row ------------------------------------------------

func _refresh_info() -> void:
	if _odds_label == null:
		return
	if _banners.is_empty():
		_odds_label.text = "Odds unavailable"
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


# --- rewarded ads (T-015) ----------------------------------------------------

func _build_ad(parent: Control) -> void:
	_ad_row = HBoxContainer.new()
	_ad_row.name = "AdRow"
	_ad_row.add_theme_constant_override("separation", 12)
	parent.add_child(_ad_row)

	_ad_label = Label.new()
	_ad_label.name = "AdLabel"
	_ad_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ad_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ad_row.add_child(_ad_label)

	_ad_button = Button.new()
	_ad_button.name = "AdButton"
	_ad_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_ad_button.pressed.connect(_on_ad_pressed)
	_ad_button.button_down.connect(func(): _tap_feedback(_ad_button))
	_ad_row.add_child(_ad_button)


func _refresh_ad() -> void:
	if _ad_row == null:
		return
	var ads_enabled := bool(_home.get("ads_enabled", false))
	var ads_today := int(_home.get("ads_today", 0))
	var max_ads := Ads.MAX_ADS_PER_DAY
	_ad_row.visible = ads_enabled
	if not ads_enabled:
		return
	var remaining := maxi(max_ads - ads_today, 0)
	_ad_label.text = "Watch ad for gems (%d/%d today)" % [ads_today, max_ads]
	_ad_button.text = "Watch Ad" if remaining > 0 else "Limit Reached"
	_ad_button.disabled = remaining <= 0
	_ad_button.tooltip_text = "" if remaining > 0 else "Daily ad limit reached. Come back tomorrow."


func _on_ad_pressed() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	var supabase := get_node_or_null("/root/Supabase")
	if supabase == null:
		return
	var result := Ads.request_reward(Ads.REWARD_GEMS_SMALL, _home, supabase)
	if not result.ok:
		_show_error(result.error)
		return
	# The ad SDK shows the ad; when it closes we refresh home to see the grant.
	# In tests, the stub calls back immediately. In production, we wait a moment
	# then refresh (the SSV callback is async).
	await get_tree().create_timer(1.5).timeout
	await gs.refresh_home()
	_refresh_ad()
	_refresh_daily()
	_refresh_pack()


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


func ad_button() -> Button:
	_ensure_built()
	return _ad_button


func ad_label_text() -> String:
	_ensure_built()
	return _ad_label.text


func ad_row_visible() -> bool:
	_ensure_built()
	return _ad_row.visible


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
		margin.add_theme_constant_override("margin_" + side, Tokens.space(&"s16"))
	add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", Tokens.space(&"s12"))
	margin.add_child(col)

	_build_faucet(col)
	_build_daily(col)
	_build_ad(col)
	_build_pack(col)
	_build_info(col)

	_refresh_alpha()
	_refresh_daily()
	_refresh_ad()
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
	_faucet_button.add_theme_font_override("font", Tokens.ui_font(500))
	_faucet_button.add_theme_font_size_override("font_size", Tokens.font_size(&"label"))
	_faucet_button.add_theme_color_override("font_color", Tokens.color(&"accent_secondary"))
	_faucet_button.add_theme_color_override("font_hover_color", Tokens.color(&"accent_secondary"))
	_faucet_button.add_theme_color_override("font_pressed_color", Tokens.color(&"accent"))
	_faucet_button.pressed.connect(_on_alpha_pressed)
	_faucet_button.button_down.connect(func(): _tap_feedback(_faucet_button))
	_faucet_row.add_child(_faucet_button)


func _build_daily(parent: Control) -> void:
	var strip := PanelContainer.new()
	strip.name = "DailyStrip"
	strip.add_theme_stylebox_override("panel", Surfaces.panel(1))
	parent.add_child(strip)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", Tokens.space(&"s12"))
	strip.add_child(row)

	_streak_label = Label.new()
	_streak_label.name = "StreakLabel"
	_streak_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_streak_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_streak_label.theme_type_variation = "Body"
	row.add_child(_streak_label)

	_reward_label = Label.new()
	_reward_label.name = "RewardLabel"
	_reward_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reward_label.visible = false
	_reward_label.theme_type_variation = "Body"
	_reward_label.add_theme_color_override("font_color", Tokens.color(&"reward"))
	row.add_child(_reward_label)

	_claim_button = Button.new()
	_claim_button.name = "ClaimButton"
	_claim_button.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_claim_button.pressed.connect(_on_claim_pressed)
	_claim_button.button_down.connect(func(): _tap_feedback(_claim_button))
	row.add_child(_claim_button)


func _build_pack(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "PackPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Surfaces.panel(2))
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", Tokens.space(&"s16"))
	panel.add_child(col)

	var banner_row := HBoxContainer.new()
	banner_row.name = "BannerRow"
	banner_row.add_theme_constant_override("separation", Tokens.space(&"s8"))
	col.add_child(banner_row)

	_prev_button = Button.new()
	_prev_button.name = "PrevBanner"
	_prev_button.text = "<"
	_prev_button.custom_minimum_size = Vector2(MIN_TAP_DP, MIN_TAP_DP)
	_prev_button.theme_type_variation = "ButtonGhost"
	_prev_button.add_theme_font_override("font", Tokens.ui_font(600))
	_prev_button.add_theme_font_size_override("font_size", Tokens.font_size(&"title"))
	_prev_button.add_theme_color_override("font_color", Tokens.color(&"text_secondary"))
	_prev_button.add_theme_color_override("font_hover_color", Tokens.color(&"text_primary"))
	_prev_button.add_theme_color_override("font_pressed_color", Tokens.color(&"accent"))
	_prev_button.pressed.connect(_cycle_banner.bind(-1))
	_prev_button.button_down.connect(func(): Motion.press(_prev_button))
	banner_row.add_child(_prev_button)

	_banner_label = Label.new()
	_banner_label.name = "BannerName"
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.theme_type_variation = "Title"
	banner_row.add_child(_banner_label)

	_next_button = Button.new()
	_next_button.name = "NextBanner"
	_next_button.text = ">"
	_next_button.custom_minimum_size = Vector2(MIN_TAP_DP, MIN_TAP_DP)
	_next_button.theme_type_variation = "ButtonGhost"
	_next_button.add_theme_font_override("font", Tokens.ui_font(600))
	_next_button.add_theme_font_size_override("font_size", Tokens.font_size(&"title"))
	_next_button.add_theme_color_override("font_color", Tokens.color(&"text_secondary"))
	_next_button.add_theme_color_override("font_hover_color", Tokens.color(&"text_primary"))
	_next_button.add_theme_color_override("font_pressed_color", Tokens.color(&"accent"))
	_next_button.pressed.connect(_cycle_banner.bind(1))
	_next_button.button_down.connect(func(): Motion.press(_next_button))
	banner_row.add_child(_next_button)

	# Pack art placeholder: a plain panel with the banner name, no logos. The
	# art pipeline owns real art; nothing here generates or downloads any.
	var art := PanelContainer.new()
	art.name = "PackArt"
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size = Vector2(0.0, 320.0)
	art.add_theme_stylebox_override("panel", Surfaces.panel(1))
	col.add_child(art)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	art.add_child(centre)

	_pack_label = Label.new()
	_pack_label.name = "PackName"
	_pack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pack_label.theme_type_variation = "Display"
	# Without a min width the centered label collapses and wraps mid-word; the
	# art panel is far wider than this, so it only affects the placeholder text.
	_pack_label.custom_minimum_size = Vector2(240.0, 0.0)
	centre.add_child(_pack_label)

	# The two CTAs sit after the art, i.e. in the bottom third of the panel.
	var buttons := HBoxContainer.new()
	buttons.name = "OpenButtons"
	buttons.add_theme_constant_override("separation", Tokens.space(&"s12"))
	col.add_child(buttons)

	_open_single = Button.new()
	_open_single.name = "OpenSingle"
	_open_single.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_single.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_open_single.pressed.connect(_on_open_pressed.bind(1))
	_open_single.button_down.connect(func(): _tap_feedback(_open_single))
	buttons.add_child(_open_single)

	_open_ten = Button.new()
	_open_ten.name = "OpenTen"
	_open_ten.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_ten.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_open_ten.pressed.connect(_on_open_pressed.bind(10))
	_open_ten.button_down.connect(func(): _tap_feedback(_open_ten))
	buttons.add_child(_open_ten)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.visible = false
	_hint_label.theme_type_variation = "Caption"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint_label)

	_error_label = Label.new()
	_error_label.name = "Error"
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	_error_label.theme_type_variation = "Body"
	_error_label.add_theme_color_override("font_color", Tokens.color(&"danger"))
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_error_label)

	_result_label = Label.new()
	_result_label.name = "Result"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.visible = false
	_result_label.theme_type_variation = "Body"
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result_label)


func _build_info(parent: Control) -> void:
	_info_row = VBoxContainer.new()
	_info_row.name = "InfoRow"
	_info_row.add_theme_constant_override("separation", Tokens.space(&"s8"))
	parent.add_child(_info_row)

	# Always visible, never behind a toggle: Play requires odds up front.
	_odds_label = Label.new()
	_odds_label.name = "Odds"
	_odds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odds_label.theme_type_variation = "Caption"
	_odds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_row.add_child(_odds_label)

	_pity_label = Label.new()
	_pity_label.name = "Pity"
	_pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pity_label.theme_type_variation = "Caption"
	_pity_label.add_theme_color_override("font_color", Tokens.color(&"reward"))
	_pity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_row.add_child(_pity_label)

	_holo_toggle = Chip.new()
	_holo_toggle.name = "HoloToggle"
	_holo_toggle.text = "Holo odds"
	_holo_toggle.custom_minimum_size = Vector2(0.0, MIN_TAP_DP)
	_holo_toggle.toggled.connect(_on_holo_toggled)
	_holo_toggle.button_down.connect(func(): _tap_feedback(_holo_toggle))
	_info_row.add_child(_holo_toggle)

	_holo_label = Label.new()
	_holo_label.name = "HoloOdds"
	_holo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_holo_label.visible = false
	_holo_label.theme_type_variation = "Caption"
	_holo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_row.add_child(_holo_label)


# --- screenshots ------------------------------------------------------------

func screenshot_count() -> int:
	return 5


func screenshot_setup(i: int) -> String:
	_ensure_built()
	# Poses add throwaway nodes; states must not leak into each other's shot.
	for child in get_children():
		if child.name.begins_with("Pose"):
			child.free()
	if _reward_label != null:
		_reward_label.visible = false
	match i:
		0:
			set_preview_data(_demo_home(1600, false, false, false, 0), _demo_banners())
			return "ready"
		1:
			set_preview_data(_demo_home(40, true, true, false, 0), _demo_banners())
			return "poor_claimed_alpha"
		2:
			set_preview_data(_demo_home(1600, false, false, true, 2), _demo_banners())
			return "ads_enabled_two_used"
		3:
			set_preview_data(_demo_home(100, false, false, false, 0), _demo_banners())
			_pose_claim_mid_countup()
			return "claim_mid_countup"
		_:
			set_preview_data(_demo_home(1600, false, false, false, 0), _demo_banners())
			_pose_cards_mid_flight()
			return "cards_mid_flight"


## Screenshot pose: the claim mid-count-up. The production count-up lives in
## the shell's top-bar counter; this pose shows the tab's half of the moment -
## the reward label up and the gem particles halfway from the claim button
## toward the counter above.
func _pose_claim_mid_countup() -> void:
	_reward_label.text = "+600 gems"
	_reward_label.visible = true
	var from := _claim_button.get_global_position() + _claim_button.size * 0.5
	for i in Motion.CLAIM_PARTICLE_COUNT:
		var p := GemCounter.GemIcon.new()
		p.name = "PoseParticle_%d" % i
		p.custom_minimum_size = Vector2(14, 14)
		p.size = Vector2(14, 14)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
		# Halfway up the screen, loosely spread like the production spray.
		p.global_position = from + Vector2(randf_range(-30, 30), -120.0 - randf_range(0, 60))


## Screenshot pose: the received cards mid-flight to the Collection tab. The
## production flight lives in the shell; this pose shows the same composition
## - rarity-tinted cards partway from the pack (centre) toward the Collection
## tab (bottom-right), shrinking as they go, with the dot they will light.
func _pose_cards_mid_flight() -> void:
	var ext := get_viewport_rect().size
	var rarities := ["common", "rare", "epic", "legendary", "rare"]
	for i in rarities.size():
		var card := ColorRect.new()
		card.name = "PoseFlyingCard_%d" % i
		card.color = Tokens.rarity_color(rarities[i])
		card.color.a = 0.9
		card.custom_minimum_size = Vector2(48, 72)
		card.size = Vector2(48, 72)
		card.pivot_offset = Vector2(24, 36)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		var t := 0.3 + 0.12 * i
		card.global_position = Vector2(
			ext.x * 0.5 + (ext.x * 0.5 - 80.0) * t - 24.0,
			ext.y * 0.5 + (ext.y - 100.0 - ext.y * 0.5) * t - 36.0)
		card.scale = Vector2.ONE * (1.0 - 0.45 * t)
		card.rotation = -0.2 + 0.1 * i
	# The dot the flight will light, drawn where the Collection tab sits.
	var dot := ColorRect.new()
	dot.name = "PoseNotificationDot"
	dot.color = Tokens.color(&"reward")
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size = Vector2(10, 10)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)
	dot.global_position = Vector2(ext.x * 0.5 + 30.0, ext.y - 74.0)


func _demo_home(gems: int, claimed: bool, alpha: bool, ads_enabled: bool, ads_today: int) -> Dictionary:
	return {
		"gems": gems,
		"pity": {"since_epic": 8, "since_legendary": 75, "total_pulls": 40},
		"streak": {"current": 5, "best": 7, "freezes": 1, "claimed_today": claimed},
		"alpha_mode": alpha,
		"ads_enabled": ads_enabled,
		"ads_today": ads_today,
	}


func _demo_banners() -> Array:
	return [{
		"id": "standard",
		"name": "Standard",
		"cost_single": 160,
		"cost_ten": 1600,
		"odds": {"common": 0.70, "rare": 0.20, "epic": 0.08, "legendary": 0.02},
		# Preview payload only: the real ramp comes from the server (T-013).
		"pity": {"ramp": {
			"epic": {"base": 0.05, "step": 0.004, "cap": 0.25},
			"legendary": {"base": 0.01, "step": 0.0015, "cap": 0.10},
		}},
		"holo_odds": {"none": 0.85, "silver": 0.08, "rainbow": 0.04,
			"gold": 0.02, "prism": 0.008, "galaxy": 0.002},
	}]
