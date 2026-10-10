extends "res://tests/test_case.gd"
## Phase 2 (real art in the runtime collection). Pins three things:
##   1. The compiled catalog matches the approved manifests (stable card_id ->
##      set/art_path) and never invents a mapping.
##   2. CardArt resolves a card's art from the catalog when the incoming
##      art_path is empty or in the non-loadable DB "shared/art/approved/..." form.
##   3. The deliberate placeholder contract survives: an unknown card, or a card
##      whose files are absent, still falls back to the procedural placeholder.
##
## Art may or may not be staged on disk in a given worktree (client/art/ is
## gitignored). These tests therefore assert on *resolution behavior* - which
## directory CardArt picks, and whether the result is real art or the shared
## placeholder - not on the presence of pixels. That keeps them green in CI
## (no art) and on a dev box (art staged).

const CardCatalogScript := preload("res://scripts/card/card_catalog.gd")
const CardArtScript := preload("res://scripts/card/card_art.gd")
const PlaceholderArtScript := preload("res://scripts/card/placeholder_art.gd")


## PlaceholderArt builds a fresh ImageTexture per call, so identity (==) never
## matches; compare pixels, which is what "is the placeholder" actually means.
func _is_placeholder(art: Dictionary) -> bool:
	var a: Image = art["base"].get_image()
	var b: Image = PlaceholderArtScript.base_texture().get_image()
	return a.get_data() == b.get_data()


## True when this worktree has the card's base.png staged under res://art/.
## client/art/ is gitignored, so CI has none and a dev box may have all.
func _staged(id: String) -> bool:
	var ap := str(CardCatalogScript.art_path_for(id))
	if ap.is_empty():
		return false
	var p := "res://art/" + ap.get_base_dir() + "/base.png"
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)


# --- catalog integrity ---------------------------------------------------------


func test_catalog_is_not_empty() -> void:
	assert_true(CardCatalogScript.all().size() >= 1,
			"catalog must index at least one approved card")


func test_every_catalog_entry_is_self_consistent() -> void:
	for c in CardCatalogScript.all():
		var card_id := str(c["card_id"])
		assert_true(card_id != "", "card_id never empty")
		assert_true(str(c["name"]) != "", "%s has a name" % card_id)
		assert_true(str(c["rarity"]) in ["common", "rare", "epic", "legendary"],
				"%s rarity is valid" % card_id)
		assert_true(str(c["set_id"]) != "", "%s has a set" % card_id)
		# art_path must be <set>/<card_id>/base.png and agree with the fields.
		var ap := str(c["art_path"])
		assert_eq(ap, "%s/%s/base.png" % [c["set_id"], card_id],
				"%s art_path derived from set+id" % card_id)


func test_lookup_by_id_round_trips() -> void:
	var first: Dictionary = CardCatalogScript.all()[0]
	var id := str(first["card_id"])
	assert_true(CardCatalogScript.has_card(id), "has_card finds a listed card")
	assert_eq(CardCatalogScript.by_id(id)["name"], first["name"], "by_id returns the same record")
	assert_eq(CardCatalogScript.art_path_for(id), first["art_path"], "art_path_for matches")


func test_unknown_card_is_not_in_catalog() -> void:
	assert_true(not CardCatalogScript.has_card("definitely-not-a-card"), "unknown id absent")
	assert_eq(CardCatalogScript.by_id("definitely-not-a-card"), {}, "by_id empty for unknown")
	assert_eq(CardCatalogScript.art_path_for("definitely-not-a-card"), "", "art_path empty for unknown")


func test_set_ids_are_sorted_and_nonempty() -> void:
	var sets := CardCatalogScript.set_ids()
	assert_true(sets.size() >= 1, "at least one set")
	var copy: Array = []
	copy.assign(sets)
	copy.sort()
	assert_eq(sets, copy, "set ids sorted")
	for sid in sets:
		assert_true(sid != "", "no empty set id")


# --- resolver: catalog fallback --------------------------------------------------
# Every test resets CardArt static state first (no before_each hook exists).

func test_empty_art_path_resolves_catalog_card() -> void:
	CardArtScript.reset_for_test()
	# A catalog card with NO server art_path must still resolve via the catalog:
	# to real staged art when it is on disk, to the placeholder when it is not.
	var id := str(CardCatalogScript.all()[0]["card_id"])
	var art := CardArtScript.textures_for(id, "common", "")
	assert_true(art["base"] != null, "base always filled")
	if _staged(id):
		assert_true(not _is_placeholder(art), "staged card resolves to real base art")
	else:
		assert_true(_is_placeholder(art), "unstaged card falls back to placeholder")


func test_db_shared_art_form_resolves_catalog_card() -> void:
	CardArtScript.reset_for_test()
	# The T-010 importer writes art_path as "shared/art/approved/<id>/base.png",
	# which is not loadable from res://. The resolver must fall back to the
	# catalog dir for that same card_id rather than giving up.
	var id := str(CardCatalogScript.all()[0]["card_id"])
	var art := CardArtScript.textures_for(id, "common",
			"shared/art/approved/%s/base.png" % id)
	assert_true(art["base"] != null, "base always filled")
	if _staged(id):
		assert_true(not _is_placeholder(art), "DB-form path still resolves to real art")
	else:
		assert_true(_is_placeholder(art), "unstaged card falls back to placeholder")


func test_unknown_card_with_db_form_stays_placeholder() -> void:
	CardArtScript.reset_for_test()
	# Not in the catalog AND the literal dir does not exist -> placeholder.
	var art := CardArtScript.textures_for("no-such-card", "rare",
			"shared/art/approved/no-such-card/base.png")
	assert_true(_is_placeholder(art), "unknown card falls back to placeholder")


func test_missing_files_stay_placeholder() -> void:
	CardArtScript.reset_for_test()
	# Well-formed res:// path whose files are absent -> placeholder, not a crash.
	var art := CardArtScript.textures_for("ghost", "epic", "nowhere/ghost/base.png")
	assert_true(_is_placeholder(art), "missing files fall back to placeholder")


func test_explicit_placeholder_scheme_is_honored() -> void:
	CardArtScript.reset_for_test()
	# Even for a real catalog card, an explicit "placeholder/..." art_path is a
	# deliberate request for the grey card and must NOT be overridden by art.
	var id := str(CardCatalogScript.all()[0]["card_id"])
	var art := CardArtScript.textures_for(id, "common", "placeholder/common.png")
	assert_true(_is_placeholder(art), "explicit placeholder scheme wins")


func test_reset_clears_resolution_memo() -> void:
	CardArtScript.reset_for_test()
	var id := str(CardCatalogScript.all()[0]["card_id"])
	CardArtScript.textures_for(id, "common", "")     # seeds _resolved / _missing
	CardArtScript.reset_for_test()
	# After reset the loader still works and returns a usable base.
	var art := CardArtScript.textures_for(id, "common", "")
	assert_true(art["base"] != null, "base filled after reset")
	if _staged(id):
		assert_true(not _is_placeholder(art), "real art resolves again after reset")
