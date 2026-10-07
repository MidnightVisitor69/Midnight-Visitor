extends "res://tests/test_case.gd"
## T-001: tilt math must be pure and bounded so shaders can trust it on any
## device, and damped so the parallax never jitters.

const TiltInput := preload("res://scripts/card/tilt_input.gd")


func test_gravity_flat_phone_is_neutral() -> void:
	# Flat screen-up reads (0, 0, -g): no lean.
	assert_eq(TiltInput.gravity_to_tilt(Vector3(0.0, 0.0, -9.81)), Vector2.ZERO)


func test_gravity_tilted_left_is_minus_one() -> void:
	var t: Vector2 = TiltInput.gravity_to_tilt(Vector3(-9.81, 0.0, 0.0))
	assert_almost(t.x, -1.0, 0.0005, "x")
	assert_almost(t.y, 0.0, 0.0005, "y")


func test_gravity_never_leaves_range() -> void:
	# Raw sensor values can exceed 1 g (shakes, flicks); the card must not.
	var samples: Array[Vector3] = [
		Vector3(30.0, 0.0, 0.0), Vector3(-30.0, 0.0, 0.0),
		Vector3(0.0, 30.0, 0.0), Vector3(0.0, -30.0, 0.0),
		Vector3(0.0, 0.0, 50.0), Vector3(12.0, -20.0, 7.0),
	]
	for g in samples:
		var t: Vector2 = TiltInput.gravity_to_tilt(g)
		assert_true(t.x >= -1.0 and t.x <= 1.0, "x out of range for %s: %s" % [g, t])
		assert_true(t.y >= -1.0 and t.y <= 1.0, "y out of range for %s: %s" % [g, t])


func test_drag_150px_is_half_tilt() -> void:
	assert_almost(TiltInput.drag_to_tilt(Vector2(150.0, 0.0)).x, 0.5, 0.0001)


func test_drag_clamps_beyond_full() -> void:
	assert_eq(TiltInput.drag_to_tilt(Vector2(900.0, 0.0)).x, 1.0)
	assert_eq(TiltInput.drag_to_tilt(Vector2(-900.0, 0.0)).x, -1.0)


func test_damp_approaches_without_overshoot() -> void:
	var prev := Vector2.ZERO
	var v := Vector2.ZERO
	for i in 60:
		v = TiltInput.damp(v, Vector2(1.0, 1.0), 8.0, 1.0 / 60.0)
		assert_true(v.x >= prev.x - 0.0001 and v.y >= prev.y - 0.0001,
				"must only move toward the target, frame %d" % i)
		assert_true(v.x <= 1.0001 and v.y <= 1.0001, "must not overshoot, frame %d" % i)
		prev = v
	assert_true(Vector2(1.0, 1.0).distance_to(v) < 0.01, "within 0.01 after 1 s")
