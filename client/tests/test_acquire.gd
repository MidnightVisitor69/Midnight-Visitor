extends "res://tests/test_case.gd"
## M-004 "acquire" moments - the small confirmations that show where things
## went (AGENTS.md: motion has a job):
##   1. the gem counter count-up (claim, faucet, any spend or grant)
##   2. the Collection tab's one notification dot
##   3. one sound per moment: gems per claim, acquire per pack, never per card
## Seams: Motion.count_up_value is a pure function (walkable synchronously);
## the shell's dot lives behind public methods and Sfx is injectable.

const AppShellScript := preload("res://scripts/app/app_shell.gd")


## A silent Sfx stand-in: records what would have played, touches no bus and
## no autoload.
class FakeSfx:
	extends Node
	var played: Array[String] = []

	func play(sound_name: String) -> void:
		played.append(sound_name)


## Build a shell without adding it to the tree, so _ready never fires a
## network sign-in. tab_buttons() forces the UI to build.
func _shell() -> AppShellScript:
	var s := AppShellScript.new()
	s.tab_buttons()
	return s


func _collection_button(s: AppShellScript) -> Button:
	for b in s.tab_buttons():
		if b.name == "Tab_collection":
			return b
	return null


func _dot_count(b: Button) -> int:
	# begins_with, not ==: a duplicate child is auto-renamed by Godot
	# ("NotificationDot@2") and must still count as the forbidden second dot.
	var n := 0
	for c in b.get_children():
		print("DEBUG sibling: [", c.name, "]")
		if String(c.name).begins_with("NotificationDot"):
			n += 1
	print("DEBUG dot_count: ", n)
	return n


# --- 1. the count-up -----------------------------------------------------------

## Every gem change tweens through Motion.count_up_value. Walk the whole
## curve for a grant and a spend: the shown value must stay inside the
## from..to span; an ease that overshoots past the target would read as the
## game miscounting your gems. Fault injection partner: add overshoot to
## count_up_value and this FAILS.
func test_count_up_never_overshoots_the_final_value() -> void:
	for pair in [[0, 600], [1600, 1120], [40, 1600]]:  # claim, spend, faucet
		var from_i: int = pair[0]
		var to_i: int = pair[1]
		var lo := mini(from_i, to_i)
		var hi := maxi(from_i, to_i)
		for i in 101:
			var p := float(i) / 100.0
			var shown := roundi(Motion.count_up_value(float(from_i), float(to_i), p))
			assert_true(shown >= lo and shown <= hi,
				"%d -> %d leaves the span at p=%.2f: shows %d" % [from_i, to_i, p, shown])


## And the counter must land exactly on the target: not one gem short, not
## one past, and clamped for tween progress a hair outside [0, 1].
func test_count_up_ends_exactly_on_the_final_value() -> void:
	for pair in [[0, 600], [1600, 1120], [40, 1600]]:
		var from_i: int = pair[0]
		var to_i: int = pair[1]
		assert_eq(roundi(Motion.count_up_value(float(from_i), float(to_i), 1.0)),
			to_i, "the count-up must end exactly on %d" % to_i)
	assert_almost(Motion.count_up_value(0.0, 600.0, 1.0), 600.0, 0.000001,
		"the raw curve's endpoint is exact, not approximate")
	assert_eq(roundi(Motion.count_up_value(0.0, 600.0, 1.05)), 600,
		"progress past 1 clamps to the target")
	assert_eq(roundi(Motion.count_up_value(1600.0, 1120.0, -0.05)), 1600,
		"progress before 0 clamps to the start")


# --- 2. the one notification dot -----------------------------------------------

## The dot appears when the received cards land on the Collection tab, and
## clears when the tab is opened; _select_tab is the real open path.
func test_collection_dot_appears_after_acquire_and_clears_on_open() -> void:
	var s := _shell()
	var b := _collection_button(s)
	assert_true(b != null, "the shell must have a Collection tab")
	var dot := b.find_child("NotificationDot", false, false) as Control
	assert_true(dot != null, "the Collection tab must own its dot")
	assert_true(not dot.visible, "no dot before anything arrives")
	s.show_collection_dot()
	assert_true(dot.visible, "the acquire arrival lights the dot")
	s._select_tab(AppShellScript.TAB_COLLECTION)
	assert_true(not dot.visible, "opening the Collection tab clears the dot")
	s.free()


## AGENTS.md: max one dot per tab. The dot node is created exactly once in
## _build_tab_bar and only ever shown/hidden, so two packs back to back can
## never stack a second dot. Fault injection partner: let show_collection_dot
## (or the builder) add a node and this FAILS.
func test_only_ever_one_dot() -> void:
	var s := _shell()
	var b := _collection_button(s)
	assert_eq(_dot_count(b), 1, "the build itself creates exactly one dot")
	s.show_collection_dot()
	s.show_collection_dot()
	s.on_collection_tab_opened()
	s.show_collection_dot()
	assert_eq(_dot_count(b), 1, "repeated acquires must not stack dots")
	s.free()


# --- 3. one sound per moment ---------------------------------------------------

## Daily claim: exactly one gems sound per claim, and the top-bar counter
## ends at the new total (a detached counter sets it directly; the tween
## needs a tree).
func test_claim_plays_one_gems_sound_and_counts_up() -> void:
	var s := _shell()
	var fake := FakeSfx.new()
	s.sfx = fake
	s.play_claim_animation(600, Vector2.ZERO)
	assert_eq(fake.played.size(), 1, "claim plays the gems sound exactly once")
	assert_eq(fake.played[0], "gems")
	assert_eq(s._gem_counter.count(), 600, "the reward lands in the counter")
	s.free()
	fake.free()


## Pack arrival: exactly one acquire sound per pack - the shell plays it in
## _arrive_collection, which only the last card's flight calls, so a 10-pull
## still plays it once. The same call bumps the tab and lights the dot.
func test_arrival_plays_one_acquire_sound_and_lights_the_dot() -> void:
	var s := _shell()
	s._screenshot_mode = true  # keep the deferred session start quiet in-tree
	tree.root.add_child(s)
	var fake := FakeSfx.new()
	s.sfx = fake
	var b := _collection_button(s)
	s._arrive_collection(b)
	assert_eq(fake.played.size(), 1, "acquire plays exactly once per pack")
	assert_eq(fake.played[0], "acquire")
	var dot := b.find_child("NotificationDot", false, false) as Control
	assert_true(dot.visible, "the arrival lights the Collection dot")
	s.free()
	fake.free()
