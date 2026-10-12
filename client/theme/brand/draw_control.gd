class_name DrawControl
extends Control
## Simple control that delegates drawing to a callable.

var draw_callable: Callable

func _draw() -> void:
	if draw_callable != null:
		draw_callable.call()