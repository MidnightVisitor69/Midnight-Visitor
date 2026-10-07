extends SceneTree
## Headless unit tests:
##   godot --headless --path client --script res://tests/run_tests.gd
## Runs every res://tests/test_*.gd (each extends test_case.gd); every method
## named test_* is one test. Exit code 1 on any failure or if nothing ran,
## because Godot itself exits 0 even when scripts fail to compile.


func _initialize() -> void:
	var passed := 0
	var failed := 0
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()

	for f in files:
		var script := load("res://tests/" + f) as GDScript
		if script == null or not script.can_instantiate():
			print("FAIL %s: does not compile" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.tree = self
			var ret = t.call(name)
			if ret is Object and ret.get_class() == "GDScriptFunctionState":
				t.failures.append("test awaited; tests must be synchronous")
			if t.failures.is_empty():
				passed += 1
				print("PASS %s::%s" % [f, name])
			else:
				failed += 1
				print("FAIL %s::%s: %s" % [f, name, "; ".join(t.failures)])

	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)
