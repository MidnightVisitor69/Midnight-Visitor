extends "res://tests/test_case.gd"
## Spec guard for client/export_presets.cfg. The dev runs
## `godot --headless --export-debug "Android"` from this repo, and the builder
## sandbox cannot run the export at all (no SDK, no export templates), so every
## fact the APK depends on is asserted here instead of being discovered on a phone.

const PRESETS_PATH := "res://export_presets.cfg"
const PROJECT_PATH := "res://project.godot"
const ANDROID := "preset.0"
const ANDROID_OPTS := "preset.0.options"
const DESKTOP := "preset.1"
const DESKTOP_OPTS := "preset.1.options"
const INTERNET_KEY := "permissions/android.permission.INTERNET"
const ANDROID_PACKAGE := "com.waifudev.cardcollector"
const ANDROID_APP_NAME := "Waifu Card Collector"


func _presets() -> ConfigFile:
	var cfg := ConfigFile.new()
	var err := cfg.load(PRESETS_PATH)
	assert_true(err == OK, "%s parses: error %s" % [PRESETS_PATH, err])
	return cfg


func _project() -> ConfigFile:
	var cfg := ConfigFile.new()
	var err := cfg.load(PROJECT_PATH)
	assert_true(err == OK, "%s parses: error %s" % [PROJECT_PATH, err])
	return cfg


## Permissions the Android preset actually turns on. Godot stores them as
## `permissions/<android permission name>` booleans in the preset options.
func _requested_permissions(cfg: ConfigFile) -> Array[String]:
	var out: Array[String] = []
	for key in cfg.get_section_keys(ANDROID_OPTS):
		if key.begins_with("permissions/") and bool(cfg.get_value(ANDROID_OPTS, key)):
			out.append(key)
	return out


## Anything the game has no business asking the player for. Play reviews reject
## undeclared-feeling permission creep, so this must stay empty.
func _permission_violations(cfg: ConfigFile) -> Array[String]:
	var bad: Array[String] = []
	for p in _requested_permissions(cfg):
		if p != INTERNET_KEY:
			bad.append(p)
	return bad


func test_android_preset_is_runnable_and_identified() -> void:
	var cfg := _presets()
	assert_true(cfg.has_section(ANDROID), "preset.0 exists")
	assert_eq(cfg.get_value(ANDROID, "name"), "Android", "preset 0 name")
	assert_eq(cfg.get_value(ANDROID, "platform"), "Android", "preset 0 platform")
	assert_eq(cfg.get_value(ANDROID, "runnable"), true, "Android preset runnable")


func test_windows_preset_is_runnable_and_identified() -> void:
	var cfg := _presets()
	assert_true(cfg.has_section(DESKTOP), "preset.1 exists")
	assert_eq(cfg.get_value(DESKTOP, "name"), "Windows Desktop", "preset 1 name")
	assert_eq(cfg.get_value(DESKTOP, "platform"), "Windows Desktop", "preset 1 platform")
	assert_eq(cfg.get_value(DESKTOP, "runnable"), true, "Windows preset runnable")


func test_presets_export_all_resources() -> void:
	var cfg := _presets()
	for section in [ANDROID, DESKTOP]:
		assert_eq(cfg.get_value(section, "export_filter"), "all_resources", "%s export_filter" % section)


func test_include_filter_ships_art() -> void:
	# Art lives outside the resource list and carries alpha; without this filter
	# the APK would ship procedural placeholders only.
	var cfg := _presets()
	for section in [ANDROID, DESKTOP]:
		var inc: String = cfg.get_value(section, "include_filter")
		assert_true(inc.contains("art/*"), "%s include_filter ships art/* (got %s)" % [section, inc])


func test_exclude_filter_drops_tests() -> void:
	var cfg := _presets()
	for section in [ANDROID, DESKTOP]:
		var exc: String = cfg.get_value(section, "exclude_filter")
		assert_true(exc.contains("tests/*"), "%s exclude_filter drops tests/* (got %s)" % [section, exc])


func test_android_package_identity() -> void:
	# No real names anywhere: the package is a neutral dev namespace.
	var cfg := _presets()
	assert_eq(cfg.get_value(ANDROID_OPTS, "package/unique_name"), ANDROID_PACKAGE, "package name")
	assert_eq(cfg.get_value(ANDROID_OPTS, "package/name"), ANDROID_APP_NAME, "app label")


func test_android_is_arm64_only() -> void:
	# The dev's phone is a Pixel 6 (arm64); shipping the other ABIs doubles the
	# APK size for nothing and makes debug installs slower.
	var cfg := _presets()
	for abi in ["armeabi-v7a", "x86", "x86_64"]:
		assert_eq(cfg.get_value(ANDROID_OPTS, "architectures/" + abi), false, "%s disabled" % abi)
	assert_eq(cfg.get_value(ANDROID_OPTS, "architectures/arm64-v8a"), true, "arm64-v8a enabled")


func test_android_sdk_levels_and_gradle_off() -> void:
	var cfg := _presets()
	assert_eq(cfg.get_value(ANDROID_OPTS, "gradle_build/min_sdk"), "24", "min_sdk")
	assert_eq(cfg.get_value(ANDROID_OPTS, "gradle_build/target_sdk"), "35", "target_sdk")
	assert_eq(cfg.get_value(ANDROID_OPTS, "gradle_build/use_gradle_build"), false, "gradle build off")


func test_android_permissions_internet_only() -> void:
	var cfg := _presets()
	assert_eq(_requested_permissions(cfg), [INTERNET_KEY], "Android requests INTERNET and nothing else")
	assert_eq(_permission_violations(cfg), [], "no extra Android permissions")


func test_permission_scan_catches_a_second_permission() -> void:
	# The guard above is only worth anything if the scan actually notices a second
	# permission, so prove it on a synthetic preset instead of trusting the empty list.
	var clean := ConfigFile.new()
	clean.set_value(ANDROID_OPTS, INTERNET_KEY, true)
	assert_eq(_permission_violations(clean), [], "INTERNET alone is not a violation")

	var dirty := ConfigFile.new()
	dirty.set_value(ANDROID_OPTS, INTERNET_KEY, true)
	dirty.set_value(ANDROID_OPTS, "permissions/android.permission.ACCESS_NETWORK_STATE", true)
	assert_eq(_permission_violations(dirty), ["permissions/android.permission.ACCESS_NETWORK_STATE"],
		"a second permission is reported")


func test_presets_carry_no_keystore_or_secret() -> void:
	# The debug keystore lives in editor settings / env vars. A path or password in
	# the preset would be a committed secret.
	var cfg := _presets()
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			assert_false(key.begins_with("keystore/"), "%s must not store a keystore field" % section)
	var text := FileAccess.get_file_as_string(PRESETS_PATH).to_lower()
	for needle in ["keystore", "password", "passwd", ".jks", "storepassword"]:
		assert_false(text.contains(needle), "preset file must not mention %s" % needle)


func assert_false(cond: bool, msg: String) -> void:
	assert_true(not cond, msg)


func test_export_paths_point_outside_the_project() -> void:
	# Godot cannot export inside res://, and the outputs must land in the repo's
	# ignored build/ folder rather than next to the project files.
	var cfg := _presets()
	var expected := {ANDROID: "../build/waifu-debug.apk", DESKTOP: "../build/waifu.exe"}
	for section in expected.keys():
		var path: String = cfg.get_value(section, "export_path")
		assert_eq(path, expected[section], "%s export_path" % section)
		assert_true(path.begins_with("../"), "%s export_path stays outside res://" % section)


func test_export_output_dir_is_git_ignored() -> void:
	# An APK in git is an unrecoverable mess; the ignore rule must match the
	# directory the presets actually write to.
	var cfg := _presets()
	var path: String = cfg.get_value(ANDROID, "export_path")
	var dir := path.get_base_dir().get_file()
	assert_eq(dir, "build", "presets export into the build/ folder")
	var f := FileAccess.open("res://../.gitignore", FileAccess.READ)
	assert_true(f != null, ".gitignore is readable")
	if f == null:
		return
	var lines := f.get_as_text().split("\n")
	f.close()
	var ignored := false
	for raw in lines:
		if raw.strip_edges() == dir + "/":
			ignored = true
	assert_true(ignored, ".gitignore ignores %s/" % dir)


func test_android_version_and_immersive_mode() -> void:
	var cfg := _presets()
	assert_eq(cfg.get_value(ANDROID_OPTS, "version/code"), 1, "version code")
	assert_eq(cfg.get_value(ANDROID_OPTS, "version/name"), "0.1.0-alpha", "version name")
	assert_eq(cfg.get_value(ANDROID_OPTS, "screen/immersive_mode"), true, "immersive mode on")


func test_project_is_portrait() -> void:
	# 1 == portrait; the Android preset has no orientation field of its own.
	var proj := _project()
	assert_eq(proj.get_value("display", "window/handheld/orientation"), 1, "portrait orientation")


func test_project_imports_etc2_astc_for_android() -> void:
	# Without etc2/astc import the Android build draws blank cards on hardware
	# that has no desktop-format texture support.
	var proj := _project()
	assert_eq(
		proj.get_value("rendering", "textures/vram_compression/import_etc2_astc"),
		true,
		"etc2/astc import enabled for the Android build"
	)
