extends Control
## Connectivity smoke test only. Real screens come from approved Figma designs
## (AGENTS.md: never invent screens in code).

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_label)
	if not Supabase.is_signed_in():
		_label.text = "Not signed in"
		return
	var res := await Supabase.select("profiles")
	_label.text = "Connected: %s" % ("ok" if res.ok else res.error)
