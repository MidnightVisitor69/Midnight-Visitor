extends RefCounted
## Base for unit tests. Tests are synchronous: a method that awaits would
## return before its asserts run and silently pass, so the runner rejects it.

var failures: Array[String] = []
## The running SceneTree, for tests that need nodes in the tree.
var tree: SceneTree


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		failures.append(msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if actual != expected:
		failures.append("%s expected %s, got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func assert_almost(actual: float, expected: float, eps := 0.0001, msg := "") -> void:
	if absf(actual - expected) > eps:
		failures.append("%s expected ~%s, got %s" % [msg, expected, actual])
