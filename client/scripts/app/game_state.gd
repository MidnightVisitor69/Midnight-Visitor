extends Node
## Single cache of whatever the server last told us. Screens read these fields
## and listen for the signals; only GameState talks to Api, so there is one
## cache and one place to add retries (AGENTS.md: the client only displays).

signal home_changed
signal banners_changed
signal collection_changed

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
