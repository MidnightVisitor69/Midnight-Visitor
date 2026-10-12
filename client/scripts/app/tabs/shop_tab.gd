extends Control
## Shop tab (T-017): renders published prices from the server via get_shop().
## Hidden behind Config.SHOP_ENABLED in the shell; do not change that gate.
##
## Every displayed number comes from the RPC payload — no hardcoded prices.

var _shop: Dictionary = {}
var _preview_mode := false

## Injectable Settings (tests); null means the autoload.
var settings: Node = null

func _ready() -> void:
	_ensure_built()
	call_deferred("_begin")

func _begin() -> void:
	if _preview_mode:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var res: Dictionary = await gs.api.get_shop()
	_shop = res.get("data", {})

func set_preview_data(shop: Dictionary) -> void:
	_preview_mode = true
	_set_data(shop)

func _set_data(shop: Dictionary) -> void:
	_shop = shop if shop is Dictionary else {}

func _has(key: String) -> bool:
	return _shop.has_key(key) and _shop[key] != null

func _get_int(key: String, default: int = 0) -> int:
	return int(_shop[key]) if _has(key) else default

func _get_dict(key: String) -> Dictionary:
	return _shop[key] as Dictionary if _has(key) else {}

func _refresh_shop() -> void:
	if not _has("packs"):
		return

	# --- Pack rows -------------------------------------------------------
	var packs: Array = _shop["packs"] as Array
	for pack in packs:
		if not (pack is Dictionary):
			continue
		var id := pack.has("id") ? pack["id"] as String : "unknown"
		var usd := _get_int("usd_cents")
		var gems := _get_int("gems")
		var first_buy := _get_int("first_buy_double_gems")

		var row = HBoxContainer.new()
		row.name = "PackRow_" + id
		row.add_theme_constant_override("separation", 8)
		add_child(row)

		var label = Label.new()
		label.name = "PackLabel"
		# Build display text only from payload values; no hardcoded numbers.
		var price_part := ""
		if _has("packs") and _shop["packs"] is Array and pack in _shop["packs"] as Array:
			price_part = "%s — $%d, %d gems, first-buy %d" % [id, usd, gems, first_buy]
		else:
			price_part = "%s — $%d, %d gems" % [id, usd, gems]
		label.text = price_part
		label.theme_type_variation = "Caption"
		label.add_theme_font_override("font", Tokens.ui_font(500))
		row.add_child(label)

	# --- Monthly Pass row ------------------------------------------------
	if _has("monthly_pass"):
		var mp := _shop["monthly_pass"] as Dictionary
		var mp_usd := _get_int("usd_cents")
		var mp_daily := _get_int("daily_gems")
		var mp_days := _get_int("days")
		var mp_upfront := _get_int("upfront_gems")
		var mp_total := mp_upfront + (mp_daily * mp_days)

		var mp_row = HBoxContainer.new()
		mp_row.name = "MonthlyPassRow"
		mp_row.add_theme_constant_override("separation", 8)
		add_child(mp_row)

		var mp_label = Label.new()
		mp_label.name = "MonthlyPassLabel"
		mp_label.text = "Monthly Pass — $%d (upfront %d gems, %d daily × %d days = %d gems total)" % [mp_usd, mp_upfront, mp_daily, mp_days, mp_total]
		mp_label.theme_type_variation = "Caption"
		mp_label.add_theme_font_override("font", Tokens.ui_font(500))
		mp_row.add_child(mp_label)

		# Best-value note: computed from the same JSON payload.
		var best_note = Label.new()
		best_note.name = "BestValueNote"
		best_note.text = "Best value: %d gems / $%d" % [mp_total, mp_usd]
		best_note.theme_type_variation = "Caption"
		best_note.add_theme_font_override("font", Tokens.ui_font(500))
		mp_row.add_child(best_note)

	# --- Ad-Free Pass row ------------------------------------------------
	if _has("ad_free_pass"):
		var afp := _shop["ad_free_pass"] as Dictionary
		var afp_usd := _get_int("usd_cents")

		var afp_row = HBoxContainer.new()
		afp_row.name = "AdFreePassRow"
		afp_row.add_theme_constant_override("separation", 8)
		add_child(afp_row)

		var afp_label = Label.new()
		afp_label.name = "AdFreePassLabel"
		afp_label.text = "Ad-Free Pass — $%d (one-time)" % afp_usd
		afp_label.theme_type_variation = "Caption"
		afp_label.add_theme_font_override("font", Tokens.ui_font(500))
		afp_row.add_child(afp_label)

	# --- Streak repair row -----------------------------------------------
	if _has("streak_repair"):
		var sr := _shop["streak_repair"] as Dictionary
		var sr_gem_cost := _get_int("gem_cost")

		var sr_row = HBoxContainer.new()
		sr_row.name = "StreakRepairRow"
		sr_row.add_theme_constant_override("separation", 8)
		add_child(sr_row)

		var sr_label = Label.new()
		sr_label.name = "StreakRepairLabel"
		sr_label.text = "Streak repair: %d gems" % sr_gem_cost
		sr_label.theme_type_variation = "Caption"
		sr_label.add_theme_font_override("font", Tokens.ui_font(500))
		sr_row.add_child(sr_label)

# --- readouts for tests and other tabs ---

func shop_data() -> Dictionary:
	_ensure_built()
	return _shop

func monthly_pass_best_value() -> Dictionary:
	_ensure_built()
	if not _has("monthly_pass"):
		return {}
	var mp := _shop["monthly_pass"] as Dictionary
	var mp_upfront := _get_int("upfront_gems")
	var mp_daily := _get_int("daily_gems")
	var mp_days := _get_int("days")
	var mp_total := mp_upfront + (mp_daily * mp_days)
	return {"total_gems": mp_total, "usd_cents": _get_int("usd_cents")}

func ad_free_pass_usd() -> int:
	_ensure_built()
	return _get_int("ad_free_pass", {}).get("usd_cents", 0)

func streak_repair_gem_cost() -> int:
	_ensure_built()
	return _get_int("streak_repair", {}).get("gem_cost", 0)