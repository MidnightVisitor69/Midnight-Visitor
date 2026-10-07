class_name Format
extends RefCounted
## Pure display formatting shared by screens. Settings is built in the design
## lane (D-003) but it has to show profiles.total_spent_cents, so the money
## format lives here: one tested helper instead of a format string pasted into
## a screen. No nodes, no network.

## Thousands separators on a digit string: "123456" -> "123,456".
static func group_thousands(digits: String) -> String:
	var out := ""
	var count := digits.length()
	for i in count:
		# A comma every three digits from the right, never before the first.
		if i > 0 and (count - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## Cents to a player-facing amount: 0 -> "$0.00", 123456 -> "$1,234.56".
## The modulo carries the cents; integer division alone drops them (199 / 100 is
## 1, not 1.99), which is why the two are not collapsed into one division.
static func cents_to_text(cents: int) -> String:
	var total := absi(cents)
	var dollars := group_thousands(str(total / 100))
	return "%s$%s.%02d" % ["-" if cents < 0 else "", dollars, total % 100]