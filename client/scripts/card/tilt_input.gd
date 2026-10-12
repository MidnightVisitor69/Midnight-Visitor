class_name TiltInput
extends Node
## One source of truth for "how is the card tilted", in [-1, 1] on both axes.
## Mobile reads the accelerometer (Input.get_gravity()); desktop/editor uses a
## drag over the card. The math lives in static functions so it is unit-testable
## without a device, and the output is exponentially damped so shaders never
## jitter.

## Drag distance that maps to full tilt.
const FULL_DRAG_PX := 300.0
const STANDARD_GRAVITY := 9.81
const DEFAULT_DAMP_RATE := 9.0

## Player settings (D-003), owned by Settings and mirrored here as statics so
## the card lane never has to look up an autoload. Defaults match the old
## behaviour exactly: sensor when mobile, full sensitivity.
static var tilt_mode := "gyroscope"
static var sensitivity := 1.0

## Smoothed tilt, safe to feed straight into a shader uniform.
var tilt := Vector2.ZERO

var _target := Vector2.ZERO
var _drag_accum := Vector2.ZERO
var _dragging := false
var _damp_rate := DEFAULT_DAMP_RATE
## "Neutral" gravity captured by re-centering: whatever the player's natural
## hold is, the card reads flat there. Static, because the Re-center button
## levels every card at once.
static var neutral := Vector2.ZERO
## Bumped by recenter(); each live input zeroes itself on its next frame.
static var recenter_seq := 0

var _seen_recenter := 0


## Re-center: the current hold becomes level. Called by the Settings screen's
## Re-center button; a no-op on desktop, where drag is already relative.
static func recenter() -> void:
	if tilt_mode != "drag" and OS.has_feature("mobile"):
		neutral = gravity_to_tilt(Input.get_gravity())
	else:
		neutral = Vector2.ZERO
	recenter_seq += 1


## Gravity in device space -> tilt. Flat screen-up reads (0, 0, -g), so a
## neutral reading gives zero tilt; leaning a side pushes gravity onto x/y.
static func gravity_to_tilt(g: Vector3) -> Vector2:
	var raw := Vector2(g.x, g.y) / STANDARD_GRAVITY
	return Vector2(clampf(raw.x, -1.0, 1.0), clampf(raw.y, -1.0, 1.0))


## Drag distance in pixels -> tilt. 300 px is a full lean.
static func drag_to_tilt(delta: Vector2) -> Vector2:
	var raw := delta / FULL_DRAG_PX
	return Vector2(clampf(raw.x, -1.0, 1.0), clampf(raw.y, -1.0, 1.0))


## Exponential smoothing: frame-rate independent and cannot overshoot.
static func damp(current: Vector2, target: Vector2, rate: float, dt: float) -> Vector2:
	var f := 1.0 - exp(-maxf(rate, 0.0) * maxf(dt, 0.0))
	return current.lerp(target, f)


## Mouse/touch press over the card. The drag is accumulated from the press
## point so small finger movements still build up to a lean.
func begin_drag() -> void:
	_dragging = true
	_drag_accum = Vector2.ZERO
	_target = Vector2.ZERO


func add_drag(relative: Vector2) -> void:
	if tilt_mode == "off":
		return
	_dragging = true
	_drag_accum += relative
	_target = drag_to_tilt(_drag_accum) * sensitivity


## Release eases back to neutral (handled by _process damping toward _target).
func end_drag() -> void:
	_dragging = false
	_drag_accum = Vector2.ZERO
	_target = Vector2.ZERO


func _process(delta: float) -> void:
	if _seen_recenter != recenter_seq:
		# The Re-center button fired: this card starts from level again.
		_seen_recenter = recenter_seq
		_target = Vector2.ZERO
		_drag_accum = Vector2.ZERO
		tilt = Vector2.ZERO
	if tilt_mode == "off":
		tilt = damp(tilt, Vector2.ZERO, _damp_rate, delta)
		return
	if not _dragging and tilt_mode == "gyroscope" and _has_accelerometer():
		_target = (gravity_to_tilt(Input.get_gravity()) - neutral) * sensitivity
	tilt = damp(tilt, _target, _damp_rate, delta)


func _has_accelerometer() -> bool:
	return OS.has_feature("mobile")
