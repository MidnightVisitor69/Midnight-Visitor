extends "res://tests/test_case.gd"
## D-003: the Settings autoload and the Settings screen.
##
## Covers what the task promises and nothing that would pass either way:
##   - persistence round-trips through user://settings.cfg
##   - the legacy Sfx [audio] enabled key is migrated
##   - text scale actually changes theme font sizes
##   - reduce_motion caps essential Motion beats at 40 ms
##   - holo intensity / tilt mode / quick open / skip tear reach their lanes
##   - deleting an account needs two confirmations
##   - every row and every interactive control is >= 48 dp
##   - every interactive control carries an accessibility_name
##
## Fault injection (marked "Guard:") is deliberate; each one FAILS when its
## guard is removed:
##   - one-step delete        -> test_delete_account_needs_two_confirmations
##   - a missing a11y name    -> test_every_interactive_control_has_a_name
##   - text scale not applied -> test_text_scale_changes_theme_font_sizes
##   - reduce_motion ignored  -> test_reduce_motion_caps_essential_beats

const SettingsScript := preload("res://scripts/settings/settings.gd")
const SettingsScreenScript := preload("res://scripts/settings/settings_screen.gd")
const AppShellScript := preload("res://scripts/app/app_shell.gd")
const PackOpeningScript := preload("res://scripts/app/pack_opening.gd")
const CardViewScript := preload("res://scripts/card/card_view.gd")
const HomeTabScript := preload("res://scripts/app/tabs/home_tab.gd")
const RarityMarkerScript := preload("res://scripts/ui/components/rarity_marker.gd")

const MIN_ROW := 48.0
const APP_VERSION := "0.1.0-alpha"


# --- helpers -----------------------------------------------------------------

func _settings(name: String) -> SettingsScript:
	# Always start from defaults: a previous run's file must not leak a setting
	# into this one (tests mutate and persist on purpose).
	var path := "user://test_d003_%s.cfg" % name
	_remove(path)
	var s: SettingsScript = SettingsScript.new()
	s.config_path = path
	s.reload()
	return s


func _screen(name := "screen") -> SettingsScreenScript:
	var screen: SettingsScreenScript = SettingsScreenScript.new()
	screen.settings = _settings(name)
	screen.set_preview_data(SettingsScreenScript._demo_home(),
			SettingsScreenScript._demo_banners(), "8f3c1a52-9d4e-4b21-a7c0-6e2d5b8f1043")
	return screen


## screen.settings is a plain property, not a child node: freeing the screen
## alone leaves the Settings node behind (it showed up as leaked ObjectDB
## instances at exit). Every test that built a screen must free through here.
func _free_screen(screen: SettingsScreenScript) -> void:
	if screen.settings != null:
		screen.settings.free()
	screen.free()


func _tex() -> ImageTexture:
	var img := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


func _art() -> Dictionary:
	return {"base": _tex(), "depth": _tex(), "char": _tex(), "bg": _tex()}


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- persistence -------------------------------------------------------------

func test_settings_persist_round_trip() -> void:
	var path := "user://test_d003_round_trip.cfg"
	_remove(path)
	var a: SettingsScript = SettingsScript.new()
	a.config_path = path
	a.reload()
	a.reduce_motion = true
	a.text_scale = 1.15
	a.holo_intensity = 40
	a.card_tilt_mode = "drag"
	a.haptics_on = false
	a.quick_open = true

	var b: SettingsScript = SettingsScript.new()
	b.config_path = path
	b.reload()
	assert_eq(b.reduce_motion, true, "reduce_motion survives")
	assert_almost(b.text_scale, 1.15, 0.0001, "text_scale survives")
	assert_eq(b.holo_intensity, 40, "holo_intensity survives")
	assert_eq(b.card_tilt_mode, "drag", "card_tilt_mode survives")
	assert_eq(b.haptics_on, false, "haptics_on survives")
	assert_eq(b.quick_open, true, "quick_open survives")

	# Leave global state as we found it for the lanes that read it.
	a.reduce_motion = false
	a.holo_intensity = 100
	a.card_tilt_mode = "gyroscope"
	a.haptics_on = true
	a.free()
	b.free()
	_remove(path)


func test_settings_change_signal_names_the_key() -> void:
	var s := _settings("signal")
	var seen := []
	s.changed.connect(func(key: String) -> void: seen.append(key))
	s.quick_open = true
	assert_eq(seen, ["quick_open"], "one signal, the key that changed")
	s.free()


func test_settings_migrates_the_legacy_sfx_toggle() -> void:
	# M-001 wrote [audio] enabled before Settings existed; an old install must
	# keep its mute state.
	var path := "user://test_d003_legacy.cfg"
	_remove(path)
	var legacy := ConfigFile.new()
	legacy.set_value("audio", "enabled", false)
	legacy.save(path)

	var s: SettingsScript = SettingsScript.new()
	s.config_path = path
	s.reload()
	assert_almost(s.sfx_volume, 0.0, 0.0001, "old Sfx-off becomes volume 0")
	# Any later write mirrors the key back for an older build to read.
	s.high_contrast = true
	var check := ConfigFile.new()
	check.load(path)
	assert_eq(check.get_value("settings", "sfx_volume", -1.0), 0.0, "new section written")
	assert_eq(check.get_value("audio", "enabled", true), false, "legacy key mirrored")
	s.free()
	_remove(path)


# --- text scale --------------------------------------------------------------

## Guard: _scale_fonts. Delete it and every size comes back unscaled.
func test_text_scale_changes_theme_font_sizes() -> void:
	var s := _settings("theme")
	var base: Theme = load("res://theme/app_theme.tres")
	var normal := s.theme_for(base)
	var button_normal := normal.get_font_size("font_size", "Button")
	assert_true(button_normal > 0, "precondition: the theme carries a Button size")
	s.text_scale = 1.5
	var big := s.theme_for(base)
	assert_true(big.get_font_size("font_size", "Button") > button_normal,
			"1.5x must enlarge the theme size")
	s.text_scale = 1.0
	assert_eq(s.theme_for(base).get_font_size("font_size", "Button"), button_normal,
			"scale 1.0 leaves the token size alone")
	assert_eq(s.text_size_name(), "default")
	s.free()


func test_text_size_names_map_to_scales() -> void:
	var s := _settings("size")
	s.set_text_size("large")
	assert_almost(s.text_scale, float(SettingsScript.TEXT_SCALES["large"]), 0.0001)
	assert_eq(s.text_size_name(), "large")
	s.set_text_size("xlarge")
	assert_eq(s.text_size_name(), "xlarge")
	s.free()


# --- reduce motion -----------------------------------------------------------

## Guard: motion_ms / Motion.scaled_ms. Remove the cap and 520 ms comes back.
func test_reduce_motion_caps_essential_beats() -> void:
	var s := _settings("motion")
	var was := Motion.reduced
	s.reduce_motion = true
	assert_true(Motion.reduced, "the flag the shaders read is set")
	assert_true(s.motion_ms(Motion.PACK_TEAR_MS) <= 40.0, "essential beats <= 40 ms")
	assert_true(Motion.scaled_ms(Motion.PACK_TEAR_MS) <= 40.0, "the same rule on Motion")
	assert_almost(s.motion_ms(Motion.PACK_SHAKE_MS), 40.0, 0.001)
	s.reduce_motion = false
	assert_almost(s.motion_ms(Motion.PACK_TEAR_MS), Motion.PACK_TEAR_MS, 0.001,
			"normal motion is untouched")
	Motion.reduced = was
	s.free()


# --- other lanes read the settings ------------------------------------------

func test_holo_intensity_reaches_the_card_lane() -> void:
	var s := _settings("holo")
	var was := CardView.holo_scale
	s.holo_intensity = 50
	assert_almost(CardView.holo_scale, 0.5, 0.001, "Settings drives the card's foil knob")
	var v: CardView = CardViewScript.new()
	v.set_card("rare", _art())
	v.set_variant("gold")
	var mat := v._holo.material as ShaderMaterial
	assert_almost(float(mat.get_shader_parameter("intensity")),
			CardView.HOLO_INTENSITY * 0.5, 0.001, "half intensity reaches the shader")
	v.free()
	s.holo_intensity = 100
	CardView.holo_scale = was
	s.free()


func test_tilt_setting_reaches_the_input() -> void:
	var s := _settings("tilt")
	var was_mode := TiltInput.tilt_mode
	var was_sens := TiltInput.sensitivity

	s.card_tilt_mode = "off"
	s.tilt_sensitivity = 0.25
	assert_eq(TiltInput.tilt_mode, "off", "mode reaches the input")
	var off := TiltInput.new()
	off.add_drag(Vector2(300.0, 0.0))
	assert_eq(off._target, Vector2.ZERO, "off means a drag produces no lean")
	off.free()

	s.card_tilt_mode = "drag"
	var on := TiltInput.new()
	on.add_drag(Vector2(300.0, 0.0))
	assert_almost(on._target.x, 0.25, 0.001, "sensitivity scales the lean")
	on.tilt = Vector2(0.5, 0.5)
	TiltInput.recenter()
	on._process(0.016)
	assert_eq(on.tilt, Vector2.ZERO, "re-center levels the card")
	on.free()

	TiltInput.tilt_mode = was_mode
	TiltInput.sensitivity = was_sens
	s.free()


func test_pack_opening_reads_quick_open_and_skip_tear() -> void:
	assert_true(not PackOpeningScript.wants_quick_open(null),
			"no settings keeps the full moment")
	assert_true(not PackOpeningScript.wants_skip_tear(null))
	var s := _settings("pack")
	s.quick_open = true
	s.skip_tear_animation = true
	assert_true(PackOpeningScript.wants_quick_open(s), "quick open reaches the reveal")
	assert_true(PackOpeningScript.wants_skip_tear(s), "skip tear reaches the reveal")
	s.quick_open = false
	assert_true(not PackOpeningScript.wants_quick_open(s), "and it follows the toggle back")
	s.free()


func test_battery_saver_caps_fps_and_drops_particles() -> void:
	var s := _settings("battery")
	var was := CardView.particles_enabled
	s.battery_saver = true
	assert_eq(Engine.max_fps, 30, "30 fps cap")
	assert_true(not CardView.particles_enabled, "particles off")
	var v: CardView = CardViewScript.new()
	v.set_card("legendary", _art())
	v.set_variant("rainbow")
	assert_true(not v._particles.emitting, "legendary sparkles stay off")
	v.free()
	s.battery_saver = false
	assert_eq(Engine.max_fps, 0, "cap lifted")
	assert_true(CardView.particles_enabled, "particles come back")
	CardView.particles_enabled = was
	s.free()


func test_confirm_before_spending_gems_is_wired() -> void:
	var s := _settings("spend")
	assert_true(not HomeTabScript.needs_spend_confirm(null, 160), "no settings: no prompt")
	assert_true(HomeTabScript.needs_spend_confirm(s, 160), "default ON prompts")
	s.confirm_spend_gems = false
	assert_true(not HomeTabScript.needs_spend_confirm(s, 160), "off means no prompt")
	assert_true(not HomeTabScript.needs_spend_confirm(s, 0), "a free pull never prompts")
	s.free()


func test_colorblind_rarity_drives_the_marker_label() -> void:
	var s := _settings("cbrarity")
	var marker: RarityMarker = RarityMarkerScript.new()
	marker.settings = s
	marker.set_rarity("epic")
	marker._ready()
	assert_true(marker.colorblind_safe(), "default is ON")
	assert_true(marker._label.visible, "default shows shape AND label")
	s.colorblind_rarity = false
	marker._apply()
	assert_true(not marker.colorblind_safe(), "setting reaches the marker")
	assert_true(not marker._label.visible, "off is the compact marker")
	marker.free()
	s.free()


func test_left_handed_layout_mirrors_the_secondary_controls() -> void:
	var s := _settings("hand")
	var shell: AppShellScript = AppShellScript.new()
	shell.settings = s
	shell.is_debug = true
	shell.tab_buttons()
	var row := shell.get_node("TopBar/Row") as HBoxContainer
	var gear := shell.gear_button()
	assert_eq(row.get_child(row.get_child_count() - 1), gear, "right-handed: gear on the right")
	s.left_handed_layout = true
	shell.call("_apply_left_handed")
	assert_eq(row.get_child(0), gear, "left-handed: gear mirrors to the left")
	s.left_handed_layout = false
	shell.call("_apply_left_handed")
	assert_eq(row.get_child(row.get_child_count() - 1), gear, "and back again")
	shell.free()
	s.free()


# --- delete / sign out -------------------------------------------------------

## Guard: the two-step state machine. Deleting on the first confirm makes the
## delete_committed assertion after step 1 fail.
func test_delete_account_needs_two_confirmations() -> void:
	var screen := _screen("delete")
	assert_eq(screen.delete_stage, 0, "nothing asked yet")
	screen.request_delete()
	assert_eq(screen.delete_stage, 1, "the first ask")
	screen.confirm_delete()
	assert_eq(screen.delete_stage, 2, "the first confirm only asks again")
	assert_true(not screen.delete_committed, "one step must NOT delete")
	screen.confirm_delete()
	assert_eq(screen.delete_stage, 3, "the second confirm commits")
	assert_true(screen.delete_committed, "two confirmations delete")
	_free_screen(screen)


func test_delete_can_be_cancelled_at_either_step() -> void:
	var screen := _screen("cancel")
	screen.request_delete()
	screen.cancel_delete()
	assert_eq(screen.delete_stage, 0)
	assert_true(not screen.delete_committed)
	assert_true(not screen.overlay_visible(), "cancel closes the dialog")
	_free_screen(screen)


func test_sign_out_needs_a_confirmation() -> void:
	var screen := _screen("signout")
	screen.request_sign_out()
	assert_eq(screen.sign_out_stage, 1)
	assert_true(not screen.sign_out_committed, "asking is not signing out")
	screen.confirm_sign_out()
	assert_true(screen.sign_out_committed, "confirming signs out")
	_free_screen(screen)


# --- layout + accessibility --------------------------------------------------

func test_every_setting_row_is_tap_sized() -> void:
	var screen := _screen("rows")
	assert_true(screen.rows().size() >= 12, "the screen actually built its rows")
	for row in screen.rows():
		var h := maxf(row.custom_minimum_size.y, row.size.y)
		assert_true(h >= MIN_ROW, "%s must be >= 48 dp, got %.1f" % [row.name, h])
	_free_screen(screen)


func test_every_interactive_control_is_tap_sized() -> void:
	var screen := _screen("controls")
	for c in screen.interactive_controls():
		var h := maxf(c.custom_minimum_size.y, c.size.y)
		assert_true(h >= MIN_ROW, "%s must be >= 48 dp, got %.1f" % [c.name, h])
	_free_screen(screen)


## Guard: an accessibility_name on every control. Drop one and this fails.
func test_every_interactive_control_has_a_name() -> void:
	var screen := _screen("a11y")
	assert_true(screen.interactive_controls().size() >= 12, "the screen has real controls")
	for c in screen.interactive_controls():
		var value: Variant = c.get("accessibility_name")
		assert_true(value != null and not str(value).is_empty(),
				"%s has no accessibility_name" % c.name)
	_free_screen(screen)


func test_the_shell_controls_are_named_too() -> void:
	var s := _settings("shell_a11y")
	var shell: AppShellScript = AppShellScript.new()
	shell.settings = s
	shell.is_debug = true
	shell.tab_buttons()
	for c in shell.shell_controls():
		var value: Variant = c.get("accessibility_name")
		assert_true(value != null and not str(value).is_empty(),
				"shell %s has no accessibility_name" % c.name)
	shell.free()
	s.free()


# --- account / info values ---------------------------------------------------

func test_info_rows_show_real_account_values() -> void:
	var screen := _screen("info")
	# _demo_home: 1999 cents, guest, version 0.1.0-alpha.
	assert_eq(screen._value_labels["lifetime"].text, "$19.99", "lifetime spend")
	assert_eq(screen._value_labels["guest"].text, "Guest account", "guest status")
	assert_eq(screen._value_labels["player_id"].text, "8f3c1a52-9d4e-4b21-a7c0-6e2d5b8f1043")
	assert_eq(screen._value_labels["version"].text, APP_VERSION, "version row")
	assert_true(screen._value_labels["credits"].text.find("Open Font License") >= 0,
			"credits name the font licence, no real names")
	_free_screen(screen)


func test_drop_rates_page_lists_odds_pity_and_holo() -> void:
	var screen := _screen("odds")
	screen._on_drop_rates()
	assert_true(screen.overlay_visible(), "the odds page opens")
	var body: String = screen._overlay_body.text
	assert_true(body.find("Common 70.0%") >= 0, "rarity odds")
	assert_true(body.find("Epic+ guaranteed") >= 0, "pity")
	assert_true(body.find("Galaxy 0.2%") >= 0, "holo odds")
	assert_true(body.find("Pity carries across every banner") >= 0, "the pity rule")
	_free_screen(screen)


func test_privacy_and_terms_are_placeholders() -> void:
	var screen := _screen("legal")
	screen._on_privacy()
	assert_true(screen._overlay_body.text.find("before launch") >= 0, "privacy says when")
	screen._on_terms()
	assert_true(screen._overlay_body.text.find("before launch") >= 0, "terms say when")
	_free_screen(screen)


# --- screenshots -------------------------------------------------------------

func test_settings_screen_exposes_four_states() -> void:
	var screen: SettingsScreenScript = SettingsScreenScript.new()
	assert_eq(screen.screenshot_count(), 4, "top, middle, bottom, delete confirm")
	for i in 4:
		assert_true(not screen.screenshot_setup(i).is_empty(), "state %d has a label" % i)
	assert_eq(screen.delete_stage, 1, "the last state is the delete confirmation")
	_free_screen(screen)
