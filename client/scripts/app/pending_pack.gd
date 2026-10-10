class_name PendingPack
extends RefCounted
## The one file that survives a crash between "player paid" and "player saw the
## cards" (task M-002 resilience).
##
## The server's pull() already granted the cards and charged the gems in a
## single transaction before any of this plays, so the reveal is pure fun and
## this file is bookkeeping. It exists for exactly one reason: a pull must never
## be charged twice, and its result must never be lost, no matter where the app
## dies.
##
## Lifecycle:
##   begin()      state=requested   written BEFORE the request leaves
##   store_result state=unrevealed  cards in hand, nothing shown yet
##   mark_revealed(i)                the tear happened / card i finished
##   finish()      file deleted      on "Done"
##
## The idempotency key is minted once, in begin(), and read back from here for
## every retry - the server returns the stored result for a key it has seen, so
## resending is free. That is the whole trick: a new key on retry would be a
## second charge.

const DEFAULT_PATH := "user://pending_pack.json"
const STATE_REQUESTED := "requested"
const STATE_UNREVEALED := "unrevealed"

## Tests point this somewhere harmless; the game never moves it.
static var path := DEFAULT_PATH


## Write the "we are about to ask" record. Done before the request so a crash
## mid-flight leaves evidence that a key exists.
static func begin(key: String, banner_id: String, count: int) -> bool:
	if key.is_empty():
		return false
	return _write({
		"key": key,
		"banner": banner_id,
		"count": count,
		"state": STATE_REQUESTED,
		"revealed_index": -1,
		"result": {},
	})


## The key to send for this exact pack right now. A pull already in flight keeps
## its key - the server has that key's result stored - so a retry is free. Any
## other pack gets a fresh key, because it is genuinely a new purchase.
static func key_for(banner_id: String, count: int) -> String:
	var p := PendingPack.load()
	if str(p.get("state", "")) == STATE_REQUESTED \
			and str(p.get("banner", "")) == banner_id \
			and int(p.get("count", -1)) == count:
		var existing := str(p.get("key", ""))
		if not existing.is_empty():
			return existing
	return new_key()


## A pull that may already have been charged must be settled before another one
## starts, or a lost response becomes a lost pack. Blocking is the honest answer:
## the tap resolves the old pack first.
static func blocks(pending: Dictionary, banner_id: String, count: int) -> bool:
	if str(pending.get("state", "")) != STATE_REQUESTED:
		return false
	return str(pending.get("banner", "")) != banner_id or int(pending.get("count", -1)) != count


## The server answered: keep the cards so a crash during the reveal cannot lose
## them, and remember how far the player got.
static func store_result(key: String, result: Dictionary) -> bool:
	var p := PendingPack.load()
	# A stale key here means the file was replaced by a newer pull; do not
	# resurrect the old one.
	if not p.is_empty() and str(p.get("key", "")) != key:
		return false
	p["key"] = key
	p["state"] = STATE_UNREVEALED
	p["result"] = result
	p["revealed_index"] = -1
	return _write(p)


## The rip finished. Recorded so a resumed reveal does not tear a pack that is
## already open.
static func mark_torn() -> void:
	var p := PendingPack.load()
	if p.is_empty():
		return
	p["torn"] = true
	_write(p)


## Card `index` finished flipping. index is 0-based; anything below the current
## value is ignored so a late write cannot rewind the reveal.
static func mark_revealed(index: int) -> void:
	var p := PendingPack.load()
	if p.is_empty():
		return
	p["revealed_index"] = maxi(int(p.get("revealed_index", -1)), index)
	_write(p)


## "Done" was pressed: this pack is fully delivered, stop tracking it.
static func finish() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The record, or {} when there is nothing pending. A corrupt file is discarded
## with a warning rather than crashing the app: the server owns the truth, and
## the collection refresh still shows whatever was granted.
static func load() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or str((parsed as Dictionary).get("state", "")) not in [STATE_REQUESTED, STATE_UNREVEALED]:
		push_warning("PendingPack: unreadable journal at %s, discarding." % path)
		finish()
		return {}
	return parsed


## Whether a pack is mid-flight, i.e. a key exists but no cards are in hand.
static func is_requested() -> bool:
	return str(PendingPack.load().get("state", "")) == STATE_REQUESTED


static func is_unrevealed() -> bool:
	return str(PendingPack.load().get("state", "")) == STATE_UNREVEALED


## A fresh 128-bit key in the same shape SupabaseClient hands out. Generated
## here so the journal does not need the network client to exist.
static func new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func _write(record: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("PendingPack: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(record))
	return true