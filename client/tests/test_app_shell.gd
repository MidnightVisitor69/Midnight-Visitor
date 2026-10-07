extends "res://tests/test_case.gd"
## T-005: the app shell frame and boot routing. The shell is grey-box; what
## must hold is the tab set (Shop hidden), thumb-sized tab buttons, and the app
## booting into the shell by default.

const AppShellScript := preload("res://scripts/app/app_shell.gd")
const MainScript := preload("res://scripts/main.gd")
const DevFlagsScript := preload("res://scripts/dev/dev_flags.gd")
const ConfigScript := preload("res://scripts/config.gd")

const APP_SHELL_SCENE := "res://scenes/app/app_shell.tscn"
const HOLO_TEST_SCENE := "res://scenes/dev/holo_test.tscn"

const MIN_TAP_DP := 48.0


## Build a shell without adding it to the tree, so _ready never fires a
## network sign-in. tab_buttons() forces the UI to build.
func _shell() -> AppShellScript:
	var s := AppShellScript.new()
	s.tab_buttons()
	return s


func test_visible_tabs_follow_the_shop_flag() -> void:
	assert_eq(AppShellScript.visible_tab_ids(false),
		PackedStringArray(["home", "collection", "trade"]))
	assert_eq(AppShellScript.visible_tab_ids(true),
		PackedStringArray(["home", "collection", "trade", "shop"]))


func test_shop_disabled_builds_exactly_three_tabs() -> void:
	# Config.SHOP_ENABLED is false at launch (test_config pins that too).
	assert_eq(ConfigScript.SHOP_ENABLED, false, "precondition: shop is hidden")
	var s := _shell()
	assert_eq(s.tab_buttons().size(), 3, "a hidden shop must not add a tab")
	assert_eq(s.tab_ids(), PackedStringArray(["home", "collection", "trade"]))
	s.free()


func test_every_tab_button_is_thumb_sized() -> void:
	var s := _shell()
	var buttons := s.tab_buttons()
	assert_eq(buttons.size(), 3, "expected the three launch tabs")
	for b in buttons:
		var h := maxf(b.custom_minimum_size.y, b.size.y)
		assert_true(h >= MIN_TAP_DP, "%s must be >= 48 px tall, got %.1f" % [b.name, h])
	s.free()


func test_tab_button_names_match_their_ids() -> void:
	var s := _shell()
	var names := PackedStringArray()
	for b in s.tab_buttons():
		names.append(b.name.trim_prefix("Tab_"))
	assert_eq(names, PackedStringArray(["home", "collection", "trade"]))
	s.free()


# --- boot routing -----------------------------------------------------------

func test_app_is_the_default_boot_path() -> void:
	assert_eq(DevFlagsScript.START_IN_HOLO_TEST, false, "app is default after T-005")
	assert_eq(MainScript.scene_for_flag(false), APP_SHELL_SCENE)
	assert_eq(MainScript.scene_for_flag(true), HOLO_TEST_SCENE)


func test_debug_build_keeps_the_holo_bench_reachable() -> void:
	var s := _shell()
	var holo := s.get_node_or_null("TopBar/Row/HoloTestButton") as Button
	# The top-bar shortcut only exists in debug builds (OS.is_debug_build()).
	assert_eq(holo != null, OS.is_debug_build(), "holo shortcut must match debug builds")
	assert_true(s.get_node_or_null("TabBar/Tabs") != null, "tab bar must exist")
	s.free()


func test_app_shell_exposes_one_screenshot_state() -> void:
	var s := AppShellScript.new()
	assert_eq(s.screenshot_count(), 1)
	s.free()
