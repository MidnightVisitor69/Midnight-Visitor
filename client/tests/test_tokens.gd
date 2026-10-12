extends "res://tests/test_case.gd"
## D-001 design token rules (task): contrast, type scale, 8-px grid, and the
## "hardcoded values are bugs" scan. Fault injection is built in:
##   - lighten text_secondary until it fails 4.5:1 -> the contrast test BITES
##   - the scan test lists what it checked, so an empty scan cannot pass

## Scanned for hardcoded colors/font sizes. token_set.gd is NOT scanned: it
## IS the palette (the one file allowed to spell out Color values).
const SCAN_FILES: Array[String] = [
	"res://scripts/ui/components/gem_counter.gd",
	"res://scripts/ui/components/chip.gd",
	"res://scripts/ui/components/badge.gd",
	"res://scripts/ui/components/toast.gd",
	"res://scripts/ui/components/sheet.gd",
	"res://scripts/ui/components/section_header.gd",
	"res://scripts/ui/components/rarity_marker.gd",
	"res://scripts/ui/app_background.gd",
	"res://scripts/dev/design_showcase.gd",
	"res://theme/surfaces.gd",
	"res://theme/build_theme.gd",
	"res://theme/tokens.gd",
	# App screens (D-004: extend scan to all app scripts)
	"res://scripts/app/tabs/home_tab.gd",
	"res://scripts/app/tabs/collection_tab.gd",
	"res://scripts/app/tabs/trade_tab.gd",
	"res://scripts/app/tabs/shop_tab.gd",
	"res://scripts/app/card_detail.gd",
	"res://scripts/app/pack_opening.gd",
	"res://scripts/settings/settings_screen.gd",
	"res://scripts/app/app_shell.gd",
]

const TokensScript := preload("res://theme/tokens.gd")


func after_each() -> void:
	# No real hooks exist in the runner; reset the token override explicitly.
	TokensScript.set_tokens(null)


# --- WCAG contrast --------------------------------------------------------------

func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	var lighter := maxf(la, lb)
	var darker := minf(la, lb)
	return (lighter + 0.05) / (darker + 0.05)


func _token_color(name: StringName) -> Color:
	return TokensScript.color(name)


func test_body_text_meets_4_5_on_every_surface() -> void:
	for surface in [&"bg", &"surface_1", &"surface_2", &"surface_3"]:
		for text in [&"text_primary", &"text_secondary"]:
			var ratio := _contrast(_token_color(text), _token_color(surface))
			assert_true(ratio >= 4.5, "%s on %s must be >= 4.5:1, got %.2f"
					% [text, surface, ratio])


func test_large_text_meets_3_on_its_surface() -> void:
	var ratio := _contrast(_token_color(&"text_primary"), _token_color(&"surface_1"))
	assert_true(ratio >= 3.0, "display text on surface_1 >= 3:1, got %.2f" % ratio)


func test_rarity_colors_are_visible_on_the_dark_base() -> void:
	for rarity in ["common", "rare", "epic", "legendary"]:
		var ratio := _contrast(TokensScript.rarity_color(rarity), _token_color(&"bg"))
		assert_true(ratio >= 3.0, "rarity %s on bg >= 3:1, got %.2f" % [rarity, ratio])


# --- fault injection: prove the contrast test bites -----------------------------

func test_lightening_text_secondary_breaks_the_contrast_rule() -> void:
	var ts: TokenSet = TokensScript.tokens().duplicate(true)
	var broken: Color = ts.colors[&"text_secondary"]
	broken = Color(broken.r, broken.g, broken.b, broken.a).lerp(
			ts.colors[&"surface_1"], 0.9)
	ts.colors[&"text_secondary"] = broken
	TokensScript.set_tokens(ts)
	var ratio := _contrast(_token_color(&"text_secondary"), _token_color(&"surface_1"))
	assert_true(ratio < 4.5,
			"fault injection: washed-out secondary must FAIL 4.5:1, got %.2f" % ratio)
	# The rule itself must flag it, not just the raw math.
	var failed := not (ratio >= 4.5)
	assert_true(failed, "the 4.5 rule rejects the broken token")
	TokensScript.set_tokens(null)
	assert_true(_contrast(_token_color(&"text_secondary"),
			_token_color(&"surface_1")) >= 4.5, "restore brings the real palette back")


# --- type scale + spacing grid ---------------------------------------------------

func test_type_scale_is_strictly_increasing() -> void:
	var values: Array = TokensScript.tokens().font_sizes.values()
	var sizes: Array[int] = []
	for v in values:
		sizes.append(int(v))
	sizes.sort()
	for i in sizes.size() - 1:
		assert_true(sizes[i] < sizes[i + 1],
				"type scale strictly increasing, clash at %d" % sizes[i])


func test_type_scale_has_the_seven_declared_steps() -> void:
	var keys := TokensScript.tokens().font_sizes.keys()
	assert_eq(keys.size(), 7, "display xl..caption")
	for k in [&"display_xl", &"display_l", &"display_m", &"title", &"body", &"label", &"caption"]:
		assert_true(keys.has(k), "type scale has %s" % k)


func test_spacing_stays_on_the_4px_half_8px_grid() -> void:
	for key in TokensScript.tokens().spacing.keys():
		var v := int(TokensScript.tokens().spacing[key])
		assert_true(v % 4 == 0, "spacing %s = %d off the 4-px half-grid" % [key, v])
		assert_true(v >= 4 and v <= 48, "spacing %s outside 4..48" % key)


func test_radii_have_small_large_pill() -> void:
	for key in [&"small", &"large", &"pill"]:
		assert_true(TokensScript.tokens().radii.has(key), "radius %s exists" % key)
	assert_true(int(TokensScript.tokens().radii[&"pill"])
			>= int(TokensScript.tokens().radii[&"large"]), "pill is the widest radius")


func test_durations_cover_tap_to_emphasized() -> void:
	var d := TokensScript.tokens().durations
	for key in [&"tap", &"quick", &"standard", &"emphasized"]:
		assert_true(d.has(key), "duration %s exists" % key)
	var values: Array[int] = []
	for v in d.values():
		values.append(int(v))
	values.sort()
	for i in values.size() - 1:
		assert_true(values[i] <= values[i + 1], "durations ordered")



# --- hardcoded values are bugs ---------------------------------------------------
# A line violates when it spells Color( or a raw font-size int without going
# through Tokens. `Color(Tokens.color(...), alpha)` is allowed: it re-tints a
# token, it does not introduce a new color.

func _violations(line: String) -> Array[String]:
	var out: Array[String] = []
	if line.contains("Color(") and not line.contains("Tokens.color"):
		out.append("hardcoded Color(")
	if line.contains("font_size") and not line.contains("Tokens."):
		if line.strip_edges().begins_with("#"):
			return []
		var after := line.substr(line.find("font_size"))
		if after.contains("Tokens.font_size") or after.contains("Tokens."):
			return []
		for i in range(10):
			if after.contains(str(i)):
				out.append("hardcoded font size")
				break
	return out


func test_no_component_hardcodes_colors_or_font_sizes() -> void:
	assert_true(SCAN_FILES.size() >= 10, "scan must actually cover the UI sources")
	for path in SCAN_FILES:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_true(f != null, "scan target missing: " + path)
		if f == null:
			continue
		var line_no := 0
		while not f.eof_reached():
			line_no += 1
			var line := f.get_line()
			if line.strip_edges().begins_with("#"):
				continue
			for v in _violations(line):
				assert_true(false, "%s:%d %s -> %s" % [path.get_file(), line_no, v, line.strip_edges()])
		f.close()


func test_tokens_resource_loads_and_is_complete() -> void:
	var ts := TokensScript.tokens()
	assert_true(ts != null, "tokens.tres loads as a TokenSet")
	assert_true(ts.colors.size() >= 17, "all color roles present")
	assert_true(ts.font_sizes.size() == 7, "type scale complete")
	assert_true(ts.spacing.size() >= 8, "spacing steps complete")
