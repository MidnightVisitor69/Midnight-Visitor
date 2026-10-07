extends "res://tests/test_case.gd"
## T-003: the holo test bench. What must never break: commons stay foil-free,
## every menu control stays thumb-tappable, the foil slider actually reaches the
## shader, and the dev flag alone routes the app into this dev screen.

const HoloTestScript := preload("res://scripts/dev/holo_test.gd")
const MainScript := preload("res://scripts/main.gd")
const DevFlagsScript := preload("res://scripts/dev/dev_flags.gd")

const HOLO_TEST_SCENE := "res://scenes/dev/holo_test.tscn"
const APP_SHELL_SCENE := "res://scenes/app/app_shell.tscn"


# --- allowed_variants -------------------------------------------------------

func test_common_allows_none_only() -> void:
	assert_eq(HoloTestScript.allowed_variants("common"), PackedStringArray(["none"]))


func test_rare_and_up_allow_all_six() -> void:
	# Written longhand so a registry change forces this test to be revisited.
	var all_six := PackedStringArray(["none", "silver", "rainbow", "gold", "prism", "galaxy"])
	for r in ["rare", "epic", "legendary"]:
		assert_eq(HoloTestScript.allowed_variants(r), all_six, r)


func test_variant_rejected_on_common_becomes_none() -> void:
	var b := HoloTestScript.new()
	b.set_variant("galaxy")
	assert_eq(b.variant, "none", "common cannot hold a foil")
	b.free()


# --- rarity reset -----------------------------------------------------------

func test_common_rarity_drops_held_variant() -> void:
	var b := HoloTestScript.new()
	b.set_rarity("epic")
	b.set_variant("prism")
	assert_eq(b.variant, "prism", "epic keeps prism")
	b.set_rarity("common")
	assert_eq(b.variant, "none", "switching to common must drop the foil")
	b.free()


# --- tap targets ------------------------------------------------------------

func test_menu_controls_are_at_least_48dp() -> void:
	var b := HoloTestScript.new()
	var controls := b.menu_controls()
	assert_true(controls.size() >= 10, "menu must expose its controls: %d" % controls.size())
	for c in controls:
		var h := maxf(c.custom_minimum_size.y, c.size.y)
		assert_true(h >= 48.0, "%s must be >= 48dp tall, got %.1f" % [c.name, h])
	b.free()


# --- tilt source ------------------------------------------------------------

func test_device_option_is_greyed_out_without_accelerometer() -> void:
	if HoloTestScript.has_accelerometer():
		return  # real phone: the dev reviews this by hand
	var b := HoloTestScript.new()
	assert_true(b.device_option_disabled(), "device button must be disabled")
	assert_true(b.tilt_note_shown(), "must explain why device is disabled")
	b.set_tilt_source("device")
	assert_eq(b.tilt_source, "drag", "must fall back to drag without a sensor")
	b.free()


# --- foil intensity ---------------------------------------------------------

func test_intensity_reaches_the_holo_uniform() -> void:
	var b := HoloTestScript.new()
	b.set_rarity("epic")
	b.set_variant("galaxy")
	b.set_intensity(0.25)
	var mat: ShaderMaterial = b.holo_material()
	assert_true(mat != null, "galaxy foil material must exist")
	assert_almost(float(mat.get_shader_parameter("intensity")), 0.25, 0.001, "intensity")
	b.free()


# --- hide menu --------------------------------------------------------------

func test_hide_menu_toggles_nodes() -> void:
	var b := HoloTestScript.new()
	b.menu_controls()  # force the UI to build without a SceneTree
	var menu := b.get_node_or_null("DebugMenu") as Control
	var show := b.get_node_or_null("ShowButton") as Control
	assert_true(menu != null and show != null, "menu nodes must exist")
	b.set_menu_visible(false)
	assert_true(not menu.visible and show.visible, "hidden: menu gone, corner button up")
	b.set_menu_visible(true)
	assert_true(menu.visible and not show.visible, "shown: menu back, corner button hidden")
	b.free()


# --- dev routing ------------------------------------------------------------

func test_start_flag_routes_to_holo_test() -> void:
	assert_eq(MainScript.scene_for_flag(true), HOLO_TEST_SCENE, "flag on")


func test_routing_function_covers_both_branches() -> void:
	assert_eq(MainScript.scene_for_flag(true), HOLO_TEST_SCENE, "flag on")
	assert_eq(MainScript.scene_for_flag(false), APP_SHELL_SCENE, "flag off")


func test_app_shell_is_the_default_boot_path() -> void:
	# T-005 flipped the default to the app; the bench is still reachable in debug.
	assert_true(not DevFlagsScript.START_IN_HOLO_TEST, "app shell must be the default")


# --- screenshot states ------------------------------------------------------

func test_screenshot_states_match_the_brief() -> void:
	var b := HoloTestScript.new()
	assert_eq(b.screenshot_count(), 3, "three shots")
	b.screenshot_setup(0)
	assert_eq([b.rarity, b.variant, b.menu_visible], ["epic", "galaxy", true], "shot 0")
	b.screenshot_setup(1)
	assert_eq([b.rarity, b.variant, b.menu_visible], ["legendary", "gold", false], "shot 1")
	b.screenshot_setup(2)
	assert_eq([b.rarity, b.variant, b.menu_visible], ["common", "none", true], "shot 2")
	b.free()
