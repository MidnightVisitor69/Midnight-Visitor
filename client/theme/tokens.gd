class_name Tokens
extends RefCounted
## Static accessors over tokens.tres (D-001). The ONLY way any script in the
## project may obtain a color, font size, spacing step, radius, duration,
## easing or font. Hardcoded values are bugs (AGENTS.md), and test_tokens.gd
## scans component sources to prove it.
##
## Fonts come back as FontVariation over the two variable OFL fonts, one per
## role: Unbounded displays, Manrope does everything else (DESIGNER.md).

const TOKENS_PATH := "res://theme/tokens.tres"

static var _set: TokenSet
static var _font_cache: Dictionary = {}  # "<path>|<weight>" -> FontVariation


static func set_tokens(ts: TokenSet) -> void:
	## Test seam: swap in a modified set so contrast failures are provable.
	_set = ts


static func tokens() -> TokenSet:
	if _set == null:
		_set = load(TOKENS_PATH) as TokenSet
		assert(_set != null, "tokens.tres missing or not a TokenSet")
	return _set


static func color(name: StringName) -> Color:
	var c: Variant = tokens().colors.get(name)
	assert(c != null, "unknown color token '%s'" % name)
	return c


## Rarity + reward colors come through the same door as everything else.
static func rarity_color(rarity: String) -> Color:
	return color(StringName("rarity_" + rarity))


static func font_size(name: StringName) -> int:
	var v: Variant = tokens().font_sizes.get(name)
	assert(v != null, "unknown font_size token '%s'" % name)
	return int(v)


static func space(name: StringName) -> int:
	var v: Variant = tokens().spacing.get(name)
	assert(v != null, "unknown spacing token '%s'" % name)
	return int(v)


static func radius(name: StringName) -> int:
	var v: Variant = tokens().radii.get(name)
	assert(v != null, "unknown radius token '%s'" % name)
	return int(v)


static func duration(name: StringName) -> int:
	var v: Variant = tokens().durations.get(name)
	assert(v != null, "unknown duration token '%s'" % name)
	return int(v)


## "out" -> Tween.EASE_OUT etc. Callers pair with Tokens.trans(name) when the
## token names a transition, e.g. "out_back" -> TRANS_BACK.
static func ease_mode(easing_name: String) -> int:
	if easing_name.begins_with("in_out"):
		return Tween.EASE_IN_OUT
	if easing_name.begins_with("out"):
		return Tween.EASE_OUT
	return Tween.EASE_IN


static func trans(easing_name: String) -> int:
	return Tween.TRANS_BACK if easing_name.contains("_back") else Tween.TRANS_SINE


static func easing(name: StringName) -> String:
	var v: Variant = tokens().easings.get(name)
	assert(v != null, "unknown easing token '%s'" % name)
	return str(v)


static func display_font(weight := 600) -> Font:
	return _variation(tokens().font_display_path, weight)


static func ui_font(weight := 400) -> Font:
	return _variation(tokens().font_ui_path, weight)


static func _variation(path: String, weight: int) -> Font:
	var key := "%s|%d" % [path, weight]
	if _font_cache.has(key):
		return _font_cache[key]
	var base: FontFile = load(path)
	assert(base != null, "font missing: " + path)
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {"wght": weight}
	_font_cache[key] = v
	return v
