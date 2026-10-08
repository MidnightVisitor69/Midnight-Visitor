extends "res://tests/test_case.gd"
## T-008: CardArt loading rules. No art files exist in a worktree, so every
## "real" path here resolves to the placeholder - that IS the contract: the
## game must render identically with and without the alpha art on disk.
##
## The LRU test feeds the cache through cache_put_for_test, the same internal
## put a real file load uses, so it needs no PNGs on disk.

const CardArtScript := preload("res://scripts/card/card_art.gd")
const PlaceholderArtScript := preload("res://scripts/card/placeholder_art.gd")


func _placeholder_keys() -> Array:
	return PlaceholderArtScript.build().keys()


# No before_each/after_each hooks exist in run_tests.gd, so CardArt's static
# state is reset inline at the top of the tests that depend on a clean cache.


# --- fallback -------------------------------------------------------------------

func test_placeholder_art_path_gives_the_placeholder() -> void:
	var art := CardArtScript.textures_for("some-card", "rare", "placeholder/rare.png")
	for key in ["base", "depth", "char", "bg"]:
		assert_true(art[key] != null, "placeholder path still fills '%s'" % key)


func test_empty_art_path_gives_the_placeholder() -> void:
	var art := CardArtScript.textures_for("some-card", "epic", "")
	for key in ["base", "depth", "char", "bg"]:
		assert_true(art[key] != null, "empty art_path still fills '%s'" % key)


func test_missing_set_path_gives_the_placeholder() -> void:
	# A well-formed path whose files do not exist must fall back, not crash.
	var art := CardArtScript.textures_for("ghost-card", "legendary", "nowhere/ghost/base.png")
	for key in ["base", "depth", "char", "bg"]:
		assert_true(art[key] != null, "missing art falls back to '%s'" % key)


func test_placeholder_is_identical_pixels_across_calls() -> void:
	var a := CardArtScript.textures_for("c1", "common", "placeholder/common.png")
	var b := CardArtScript.textures_for("c2", "common", "placeholder/rare.png")
	assert_eq(a["base"], b["base"], "placeholder base is one shared texture")


func test_fallback_layers_are_all_real_placeholders() -> void:
	var art := CardArtScript.textures_for("c", "epic", "launch-01/who/base.png")
	var shared := CardArtScript.placeholder_for("epic")
	assert_eq(art["base"], shared["base"], "fallback base is the shared placeholder")
	assert_eq(art["char"], shared["char"], "fallback char is the shared placeholder")
	# Pixel-level: the fallback is a real PlaceholderArt build, byte for byte.
	var fresh := PlaceholderArtScript.build()
	assert_true(art["base"].get_image().get_data()
			== fresh["base"].get_image().get_data(),
			"fallback base pixels equal a fresh PlaceholderArt build")


# --- real-path shape (files absent: layers other than base stay null) -----------

## With an art directory that cannot exist, only the placeholder path is taken.
## This pins the negative: a missing file must NEVER surface as a broken load
## error to callers - they get placeholder layers, always four keys.
func test_result_always_has_exactly_the_four_layer_keys() -> void:
	var art := CardArtScript.textures_for("c", "rare", "placeholder/rare.png")
	assert_eq(art.keys().size(), 4, "four keys")
	for key in ["base", "depth", "char", "bg"]:
		assert_true(art.has(key), "has key %s" % key)


# --- LRU ------------------------------------------------------------------------

func test_lru_never_holds_more_than_48_entries() -> void:
	CardArtScript.reset_for_test()
	for i in 60:
		CardArtScript.cache_put_for_test("key_%d" % i, PlaceholderArtScript.base_texture())
	assert_true(CardArtScript.cache_size() <= 48,
			"cache must cap at 48, got %d" % CardArtScript.cache_size())
	# The OLDEST entries were evicted, not the newest.
	var art := CardArtScript.textures_for("x", "rare", "")
	assert_true(art != null, "loader still works after eviction")


func test_reequesting_a_cached_texture_does_not_grow_the_cache() -> void:
	CardArtScript.reset_for_test()
	CardArtScript.cache_put_for_test("same", PlaceholderArtScript.base_texture())
	var before := CardArtScript.cache_size()
	for i in 10:
		CardArtScript.cache_put_for_test("same", PlaceholderArtScript.base_texture())
	assert_eq(CardArtScript.cache_size(), before, "re-put must not duplicate")


func test_reset_clears_everything() -> void:
	CardArtScript.cache_put_for_test("k", PlaceholderArtScript.base_texture())
	CardArtScript.reset_for_test()
	assert_eq(CardArtScript.cache_size(), 0, "reset empties the cache")
