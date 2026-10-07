extends Node
## Single cache of whatever the server last told us. Screens read these fields
## and listen for the signals; only GameState talks to Api, so there is one
## cache and one place to add retries (AGENTS.md: the client only displays).

signal home_changed
signal banners_changed
signal collection_changed
## A pull finished (ok or error). T-007 connects this to show the reveal; until
## then Home falls back to a plain list, so the signal always fires.
signal pull_finished(result: Dictionary)

## get_home() payload, or {} before the first successful load.
var home: Dictionary = {}
## get_banners() list.
var banners: Array = []
## get_collection() list.
var collection: Array = []


func refresh_home() -> bool:
	var res: Dictionary = await Api.get_home(Supabase)
	if not bool(res.get("ok", false)):
		return false
	home = res.get("data", {})
	home_changed.emit()
	return true


func refresh_banners() -> bool:
	var res: Dictionary = await Api.get_banners(Supabase)
	if not bool(res.get("ok", false)):
		return false
	banners = res.get("data", [])
	banners_changed.emit()
	return true


func refresh_collection() -> bool:
	var res: Dictionary = await Api.get_collection(Supabase)
	if not bool(res.get("ok", false)):
		return false
	collection = res.get("data", [])
	collection_changed.emit()
	return true


# --- Home actions -----------------------------------------------------------
# Screens never call Api; every write goes through here so the cache and the
# single SupabaseClient reference stay in one place.

## claim_daily is idempotent on the calendar day (the server keys on it), so no
## key is sent. Returns the Api result so the caller can show the reward.
func claim_daily() -> Dictionary:
	return await Api.claim_daily(Supabase)


## Alpha-only gem faucet, keyed server-side so a double tap cannot double-grant.
func alpha_grant_gems() -> Dictionary:
	var res: Dictionary = await Api.alpha_grant_gems(Supabase)
	if bool(res.get("ok", false)):
		home["gems"] = int((res.get("data", {}) as Dictionary).get("gems", 0))
		home_changed.emit()
	return res


## Pull from a banner. The client only names the action; the server rolls the
## cards, the variant, and the pity move in one transaction (AGENTS.md).
func pull(banner_id: String, count: int) -> Dictionary:
	var res: Dictionary = await Api.pull(Supabase, banner_id, count)
	if bool(res.get("ok", false)):
		var data: Dictionary = res.get("data", {})
		if data.has("gems"):
			home["gems"] = int(data.get("gems", 0))
			home_changed.emit()
	pull_finished.emit(res)
	return res
