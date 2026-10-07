extends Control
## Connectivity smoke test only. Real screens come from approved Figma designs
## (AGENTS.md: never invent screens in code).

const DevFlags := preload("res://scripts/dev/dev_flags.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const HOLO_TEST_SCENE := "res://scenes/dev/holo_test.tscn"

var _label: Label


## Pure routing decision so a test can check it without swapping scenes.
static func scene_for_flag(start_in_holo_test: bool) -> String:
	return HOLO_TEST_SCENE if start_in_holo_test else MAIN_SCENE


## The scene this build boots into, per DevFlags.
func start_scene_path() -> String:
	return scene_for_flag(DevFlags.START_IN_HOLO_TEST)


func _ready() -> void:
	if DevFlags.START_IN_HOLO_TEST:
		get_tree().change_scene_to_file(HOLO_TEST_SCENE)
		return
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_label)
	if not Supabase.is_signed_in():
		_label.text = "Not signed in"
		return
	var res := await Supabase.select("profiles")
	_label.text = "Connected: %s" % ("ok" if res.ok else res.error)
