extends Control
## Boot router. The app shell is the product; the holo test bench stays
## reachable from the shell's top bar in debug builds (T-005).

const DevFlags := preload("res://scripts/dev/dev_flags.gd")

const HOLO_TEST_SCENE := "res://scenes/dev/holo_test.tscn"
const APP_SHELL_SCENE := "res://scenes/app/app_shell.tscn"


## Pure routing decision so a test can check it without swapping scenes.
static func scene_for_flag(start_in_holo_test: bool) -> String:
	return HOLO_TEST_SCENE if start_in_holo_test else APP_SHELL_SCENE


## The scene this build boots into, per DevFlags.
func start_scene_path() -> String:
	return scene_for_flag(DevFlags.START_IN_HOLO_TEST)


func _ready() -> void:
	# Deferred: the tree is still adding this scene's children in _ready.
	get_tree().call_deferred("change_scene_to_file", start_scene_path())
