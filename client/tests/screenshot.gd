extends SceneTree
## Renders a scene on the real GPU and saves PNGs. Headless Godot never
## compiles shaders, so this is the only check that shader code actually works.
##   godot --path client --script res://tests/screenshot.gd -- <scene.tscn> <out_dir>
## Optional on the scene root: screenshot_count() -> int and
## screenshot_setup(i: int) -> String (returns a label used in the file name).

const SETTLE_FRAMES := 20


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <scene> <out_dir>")
		quit(2)
		return
	_run(args[0], args[1])


func _run(scene_path: String, out_dir: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("cannot load " + scene_path)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var node := packed.instantiate()
	root.add_child(node)
	var count: int = node.screenshot_count() if node.has_method("screenshot_count") else 1
	var base := scene_path.get_file().get_basename()
	for i in count:
		var label := str(i)
		if node.has_method("screenshot_setup"):
			label = str(node.screenshot_setup(i))
		for _f in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/%s_%02d_%s.png" % [out_dir, base, i, label.validate_filename()]
		img.save_png(path)
		print("SHOT " + path)
	quit(0)
