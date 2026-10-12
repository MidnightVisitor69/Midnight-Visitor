extends SceneTree
## Dev-only: prints a coarse ASCII map of a PNG so shot contents can be judged
## without eyeballing a thumbnail.   res://tools/inspect_shot.gd -- <png> <cols>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.new()
	var err := img.load(args[0])
	if err != OK:
		quit(1)
		return
	var cols := 69
	if args.size() > 1:
		cols = int(args[1])
	var rows := int(float(cols) * float(img.get_height()) / float(img.get_width()) * 0.5)
	var chars := " .:-=+*#%@"
	var ramp := {
		"navy": Color(0.027, 0.039, 0.071),
	}
	var out := PackedStringArray()
	out.append("%s  %dx%d" % [args[0].get_file(), img.get_width(), img.get_height()])
	# Bounding box of anything brighter than the navy backdrop.
	var min_x := img.get_width()
	var min_y := img.get_height()
	var max_x := -1
	var max_y := -1
	var bgc := Color(0.03, 0.05, 0.12)
	for yy in img.get_height():
		for xx in img.get_width():
			var d := (img.get_pixel(xx, yy).r - bgc.r) * (img.get_pixel(xx, yy).r - bgc.r) \
					+ (img.get_pixel(xx, yy).g - bgc.g) * (img.get_pixel(xx, yy).g - bgc.g) \
					+ (img.get_pixel(xx, yy).b - bgc.b) * (img.get_pixel(xx, yy).b - bgc.b)
			if d > 0.0001:
				min_x = mini(min_x, xx)
				min_y = mini(min_y, yy)
				max_x = maxi(max_x, xx)
				max_y = maxi(max_y, yy)
	if max_x >= 0:
		out.append("content bbox: %d,%d -> %d,%d  (%dx%d)" % [
				min_x, min_y, max_x, max_y, max_x - min_x + 1, max_y - min_y + 1])
	for gy in rows:
		var line := ""
		for gx in cols:
			var px := img.get_pixel(
					int(float(gx) / cols * img.get_width()),
					int(float(gy) / rows * img.get_height()))
			var lum := (px.r * 0.299 + px.g * 0.587 + px.b * 0.114)
			var tag := chars[clampi(int(lum * (chars.length() - 1)), 0, chars.length() - 1)]
			# Mark hue: p=ink/print, m=magenta, g=gold, c=cyan, w=white-ish
			if lum < 0.06:
				line += " "
			elif px.r > px.g * 1.35 and px.b > px.g * 1.2:
				if lum > 0.25:
					line += tag.to_upper()
				else:
					line += tag
			elif px.r > px.g * 1.4 and px.g > px.b * 1.3:
				if lum > 0.3:
					line += "G"
				else:
					line += "g"
			elif px.g > px.r * 1.3 and px.b > px.r * 1.2:
				if lum > 0.3:
					line += "C"
				else:
					line += "c"
			elif lum > 0.6:
				if px.r > px.g + 0.1 and px.g > px.b:
					line += "W"
				else:
					line += "w"
			else:
				line += "."
		out.append(line)
	print("\n".join(out))
	quit(0)
