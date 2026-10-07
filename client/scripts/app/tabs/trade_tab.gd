extends Control
## Trade tab (T-009): an honest placeholder. Wonder Trade locks behind 3 days
## and 20 pulls, both decided server-side, so this tab states the rule and shows
## the player's pull progress instead of a button that cannot work yet.
##
## Grey-box like the other tabs: approved Figma designs replace the layout later,
## so view code lives in _build_* and state in GameState. set_preview_data() is
## the offline entry point for tests and the screenshot harness (no network).

## Mirrors the server gate in wonder_trade(): signup age and lifetime pulls.
const ACCOUNT_AGE_DAYS := 3
const PULLS_REQUIRED := 20
const EXPLAINER := "Deposit one card, get a random card of the same rarity back. Five swaps a day, then the pool resets."

## The account-age half of the gate, worded like the server's own message.
static func age_text() -> String:
	return "Unlocks %d days after sign-up" % ACCOUNT_AGE_DAYS


## "Pulls: 19/20". Clamped at the gate, so an account well past it reads
## 20/20 rather than 35/20: this row is progress, not a lifetime counter.
static func pulls_text(total_pulls: int) -> String:
	return "Pulls: %d/%d" % [clampi(total_pulls, 0, PULLS_REQUIRED), PULLS_REQUIRED]


var _preview_mode := false
var _home: Dictionary = {}

var _built := false
var _explainer: Label
var _age_label: Label
var _pulls_label: Label
var _rules_row: VBoxContainer


func _ready() -> void:
	_ensure_built()
	# Deferred so the screenshot harness and tests can set preview data first,
	# same trick as the other tabs: nothing here may reach the network.
	call_deferred("_begin")


# --- state ------------------------------------------------------------------

## Offline entry point for tests and screenshots. _preview_mode also stops the
## tab from reading GameState, so a stray call here cannot make a request.
func set_preview_data(home: Dictionary) -> void:
	_ensure_built()
	_preview_mode = true
	_set_data(home)


func _set_data(home: Dictionary) -> void:
	_home = (home as Dictionary).duplicate(true) if home is Dictionary else {}
	_refresh()


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
	_on_state_changed()


func _on_state_changed() -> void:
	if _preview_mode:
		return
	var gs := _state_node()
	if gs == null:
		return
	_set_data(gs.get("home"))


## Lifetime pulls from the get_home() cache. Missing or malformed counts as 0:
## the tab must never show a progress bar it cannot fill.
func _total_pulls() -> int:
	var pity: Variant = _home.get("pity", {})
	if not (pity is Dictionary):
		return 0
	return int((pity as Dictionary).get("total_pulls", 0))


func _refresh() -> void:
	if _pulls_label == null:
		return
	_pulls_label.text = pulls_text(_total_pulls())


# --- readouts (used by tests) -----------------------------------------------

func explanation_text() -> String:
	_ensure_built()
	return _explainer.text


func age_label_text() -> String:
	_ensure_built()
	return _age_label.text


func pulls_label_text() -> String:
	_ensure_built()
	return _pulls_label.text


func rules_row() -> Control:
	_ensure_built()
	return _rules_row


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

	_explainer = Label.new()
	_explainer.name = "Explainer"
	_explainer.text = EXPLAINER
	_explainer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_explainer)

	# One quiet panel for both gate rules; no CTA until Wonder Trade ships.
	var panel := PanelContainer.new()
	panel.name = "UnlockPanel"
	col.add_child(panel)

	_rules_row = VBoxContainer.new()
	_rules_row.name = "RulesRow"
	_rules_row.add_theme_constant_override("separation", 8)
	panel.add_child(_rules_row)

	_age_label = Label.new()
	_age_label.name = "AgeLabel"
	_age_label.text = age_text()
	_rules_row.add_child(_age_label)

	_pulls_label = Label.new()
	_pulls_label.name = "PullsLabel"
	_pulls_label.text = pulls_text(0)
	_rules_row.add_child(_pulls_label)

	_refresh()


# --- screenshots ------------------------------------------------------------

func screenshot_count() -> int:
	return 1


func screenshot_setup(_i: int) -> String:
	_ensure_built()
	# A day-one account: no network, and the pull row reads 7/20.
	set_preview_data({
		"gems": 1600,
		"pity": {"since_epic": 3, "since_legendary": 40, "total_pulls": 7},
	})
	return "locked_day_one"