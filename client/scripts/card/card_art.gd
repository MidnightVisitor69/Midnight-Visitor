class_name CardArt
extends RefCounted
## The one place any screen loads card art (T-008). Real art lives under
## res://art/<set_id>/<card_id>/ per the Handoff Contract; the importer writes
## cards.art_path as "<set_id>/<card_id>/base.png" relative to res://art/.
## Anything else - an empty path, or the test cards' "placeholder/<rarity>.png"
## - falls back to the procedural placeholder so the game always renders.
##
## The fallback is deliberate, not an error path: worktrees and CI have no art
## files at all (alpha art is never committed), so "missing file" is the normal
## state until the importer runs. Callers therefore never branch on whether art
## exists; they always get four usable layer textures.
##
## Loading strategy (T-008 spec): try the editor-imported resource first, then
## the raw file - PNGs dropped into a running project without an editor reimport
## still have to show up. Every texture goes through one LRU cache (max 48)
## shared by the collection grid, the detail view and the pack summary, so
## scrolling a few hundred tiles never re-reads files.
##
## Known-missing directories are memoized per card: a collection of placeholders
## must not pay four filesystem probes per tile per rebuild on every scroll.

const MAX_ENTRIES := 48
## Directory prefix that means "the grey test cards", never a real art folder.
const PLACEHOLDER_PREFIX := "placeholder/"
const ART_ROOT := "res://art/"

const LAYERS: Array[String] = ["base", "depth", "char", "bg"]

static var _cache: Dictionary = {}      # file path -> Texture2D
static var _order: Array[String] = []   # same keys, least-recently-used first
static var _missing: Dictionary = {}    # "<card_id>|<art_path>" -> true
static var _placeholder: Dictionary = {}
## One stable placeholder Dictionary per rarity, so tests can compare identity
## and a future rarity tint is a one-line change here.
static var _placeholder_by_rarity: Dictionary = {}


## The four art layers for one card. Keys: base/depth/char/bg, each a
## Texture2D - never null (the placeholder fills whatever the files lack).
##   card_id   provenance/debug identity; also memoizes known-missing art dirs
##   rarity    only shapes the placeholder fallback (and future rarity tint)
##   art_path  cards.art_path from the server, relative to res://art/
static func textures_for(card_id: String, rarity: String, art_path := "") -> Dictionary:
	var dir := _real_dir(art_path)
	if dir.is_empty():
		return placeholder_for(rarity)
	var memo_key := card_id + "|" + art_path
	if _missing.has(memo_key):
		return placeholder_for(rarity)
	var art := {}
	for layer in LAYERS:
		if layer != "base" and art.is_empty():
			# Base already missing: skip probing the other layers entirely.
			break
		var tex := _load_texture(ART_ROOT + dir + "/" + layer + ".png")
		if tex == null and layer == "base":
			_missing[memo_key] = true
			return placeholder_for(rarity)
		art[layer] = tex
	return art


## The shared procedural placeholder. Same pixels every call, so screenshots
## and tests stay stable (PlaceholderArt contract).
static func placeholder_for(rarity: String) -> Dictionary:
	if _placeholder.is_empty():
		_placeholder = PlaceholderArt.build()
	if not _placeholder_by_rarity.has(rarity):
		_placeholder_by_rarity[rarity] = _placeholder
	return _placeholder_by_rarity[rarity]


## Number of file-loaded textures currently held. Read by the LRU test.
static func cache_size() -> int:
	return _cache.size()


## Test seam: drop a texture into the cache the way a real file load would, so
## the LRU eviction test does not need 60 PNGs on disk.
static func cache_put_for_test(key: String, tex: Texture2D) -> void:
	_cache_put(key, tex)


## Test seam: reset all static state between tests.
static func reset_for_test() -> void:
	_cache.clear()
	_order.clear()
	_missing.clear()
	_placeholder.clear()
	_placeholder_by_rarity.clear()


# --- internals -----------------------------------------------------------------

## "<set>/<card>/base.png" -> "<set>/<card>"; "" when the path cannot name a
## real art directory (empty, or the placeholder scheme).
static func _real_dir(art_path: String) -> String:
	var p := art_path.strip_edges()
	if p.is_empty() or p.begins_with(PLACEHOLDER_PREFIX):
		return ""
	var dir := p.get_base_dir()
	if dir.is_empty() or dir == "." or dir == "/":
		return ""
	return dir


static func _load_texture(path: String) -> Texture2D:
	if _cache.has(path):
		_touch(path)
		return _cache[path]
	var tex := _read_texture(path)
	if tex != null:
		_cache_put(path, tex)
	return tex


## Editor-imported resource first (CompressedTexture2D), then the raw file for
## PNGs that were added without an editor reimport.
static func _read_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


static func _cache_put(key: String, tex: Texture2D) -> void:
	if _cache.has(key):
		# _touch already moves the key to the MRU end; appending again would
		# duplicate it in _order and make eviction drop live entries.
		_touch(key)
		_cache[key] = tex
		return
	_cache[key] = tex
	_order.append(key)
	while _order.size() > MAX_ENTRIES:
		var oldest: String = _order[0]
		_order.remove_at(0)
		_cache.erase(oldest)


static func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)
