class_name Api
extends RefCounted
## Typed wrappers around every server call. Screens never call these directly;
## GameState owns the cache and the only reference to SupabaseClient.
##
## Each wrapper returns {"ok": bool, "data": Variant, "error": String}, the same
## shape as SupabaseClient.call_rpc. Parsing lives in pure static parse_*
## functions so recorded server JSON can be checked without a network.

## Rarity odds keys, in server order.
const ODDS_KEYS: Array[String] = ["common", "rare", "epic", "legendary"]
## Holo odds keys, matching HoloVariants.VARIANTS / the DB enum.
const HOLO_KEYS: Array[String] = ["none", "silver", "rainbow", "gold", "prism", "galaxy"]
## Tiers whose per-pull odds climb with pulls since the last hit (T-013).
const RAMP_TIERS: Array[String] = ["epic", "legendary"]

const COLLECTION_QUERY := "select=id,card_id,variant,obtained_at,cards(name,rarity,set_id,art_path)&order=obtained_at.desc"


# --- RPC wrappers -----------------------------------------------------------

static func get_home(client: Node) -> Dictionary:
	var res: Dictionary = await client.call_rpc("get_home")
	return _parsed(res, "home")


static func get_set_sizes(client: Node) -> Dictionary:
	var res: Dictionary = await client.call_rpc("get_set_sizes")
	return _parsed(res, "set_sizes")


static func get_banners(client: Node) -> Dictionary:
	var res: Dictionary = await client.call_rpc("get_banners")
	return _parsed(res, "banners")


static func claim_daily(client: Node) -> Dictionary:
	# The server contract gives claim_daily no key: the calendar day is the idempotency.
	var res: Dictionary = await client.call_rpc("claim_daily")
	return _parsed(res, "daily")


static func pull(client: Node, banner_id: String, count: int) -> Dictionary:
	var res: Dictionary = await client.call_rpc("pull", pull_args(banner_id, count, client.new_idempotency_key()))
	return _parsed(res, "pull")


static func alpha_grant_gems(client: Node) -> Dictionary:
	var args := {"p_key": client.new_idempotency_key()}
	var res: Dictionary = await client.call_rpc("alpha_grant_gems", args)
	return _parsed(res, "gems")


static func get_collection(client: Node) -> Dictionary:
	var res: Dictionary = await client.select("user_cards", COLLECTION_QUERY)
	return _parsed(res, "collection")


static func get_shop(client: Node) -> Dictionary:
	var res: Dictionary = await client.call_rpc("get_shop")
	return _parsed(res, "shop")


## Google Play requires in-app account deletion. The server deletes the auth
## user and everything that cascades from it; no client data is trusted.
static func delete_my_account(client: Node) -> Dictionary:
	var res: Dictionary = await client.call_rpc("delete_my_account")
	return {"ok": bool(res.get("ok", false)), "data": res.get("data"),
			"error": str(res.get("error", ""))}


## The argument dictionary pull() sends, kept pure so a test can check the
## idempotency key is wired without awaiting a request.
static func pull_args(banner_id: String, count: int, key: String) -> Dictionary:
	return {"p_banner_id": banner_id, "p_count": count, "p_key": key}


# --- parsing ----------------------------------------------------------------

static func parse_home(d: Variant) -> Dictionary:
	var src := _dict(d)
	var pity := _dict(src.get("pity"))
	var streak := _dict(src.get("streak"))
	return {
		"gems": int(src.get("gems", 0)),
		"pity": {
			"since_epic": int(pity.get("since_epic", 0)),
			"since_legendary": int(pity.get("since_legendary", 0)),
			"total_pulls": int(pity.get("total_pulls", 0)),
		},
		"streak": {
			"current": int(streak.get("current", 0)),
			"best": int(streak.get("best", 0)),
			"last_claim": str(streak.get("last_claim", "")),
			"freezes": int(streak.get("freezes", 0)),
			"claimed_today": bool(streak.get("claimed_today", false)),
		},
		"total_spent_cents": int(src.get("total_spent_cents", 0)),
		"alpha_mode": bool(src.get("alpha_mode", false)),
		"created_at": str(src.get("created_at", "")),
		# Assume anonymous when unsure: it only ever hides account UI.
		"is_anonymous": bool(src.get("is_anonymous", true)),
		# Ads (T-015): feature flag and daily count from server.
		"ads_enabled": bool(src.get("ads_enabled", false)),
		"ads_today": int(src.get("ads_today", 0)),
	}


static func parse_banners(a: Variant) -> Array:
	var out: Array = []
	if not (a is Array):
		return out
	for item in a:
		if not (item is Dictionary):
			continue
		var b: Dictionary = item
		var pity := _dict(b.get("pity"))
		out.append({
			"id": str(b.get("id", "")),
			"name": str(b.get("name", "")),
			"cost_single": int(b.get("cost_single", 0)),
			"cost_ten": int(b.get("cost_ten", 0)),
			"ends_at": str(b.get("ends_at", "")),
			"odds": _float_map(b.get("odds"), ODDS_KEYS),
			"pity": {
				# T-013: soft pity ramp. base/step/cap are server numbers; the
				# client only formats them (no odds constants client-side).
				"ramp": _ramp_map(pity.get("ramp")),
			},
			"holo_odds": _float_map(b.get("holo_odds"), HOLO_KEYS),
		})
	return out


static func parse_pull(d: Variant) -> Dictionary:
	var src := _dict(d)
	var pity := _dict(src.get("pity"))
	var cards: Array = []
	if src.get("cards") is Array:
		for item in src["cards"]:
			if not (item is Dictionary):
				continue
			var c: Dictionary = item
			cards.append({
				"user_card_id": str(c.get("user_card_id", "")),
				"card_id": str(c.get("card_id", "")),
				"rarity": str(c.get("rarity", "common")),
				"variant": str(c.get("variant", "none")),
				"pity": int(c.get("pity", 0)),
			})
	return {
		"cards": cards,
		"gems": int(src.get("gems", 0)),
		"pity": {
			"since_epic": int(pity.get("since_epic", 0)),
			"since_legendary": int(pity.get("since_legendary", 0)),
		},
	}


static func parse_collection(a: Variant) -> Array:
	var out: Array = []
	if not (a is Array):
		return out
	for item in a:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		# PostgREST returns the joined card as a nested object.
		var card := _dict(row.get("cards"))
		out.append({
			"id": str(row.get("id", "")),
			"card_id": str(row.get("card_id", "")),
			"variant": str(row.get("variant", "none")),
			"obtained_at": str(row.get("obtained_at", "")),
			"name": str(card.get("name", "")),
			"rarity": str(card.get("rarity", "common")),
			"set_id": str(card.get("set_id", "")),
			"art_path": str(card.get("art_path", "")),
		})
	return out


static func parse_set_sizes(d: Variant) -> Dictionary:
	var out := {}
	var src := _dict(d)
	for key in src:
		out[str(key)] = int(src[key])
	return out


static func parse_daily(d: Variant) -> Dictionary:
	var src := _dict(d)
	return {
		"streak": int(src.get("streak", 0)),
		"best": int(src.get("best", 0)),
		"reward": int(src.get("reward", 0)),
		"freezes": int(src.get("freezes", 0)),
		"used_freeze": bool(src.get("used_freeze", false)),
		"gems": int(src.get("gems", 0)),
	}


static func parse_gems(d: Variant) -> Dictionary:
	return {"gems": int(_dict(d).get("gems", 0))}


static func parse_shop(d: Variant) -> Dictionary:
	var src := _dict(d)
	return {
		"pull_single": int(src.get("pull_single", 0)),
		"pull_ten": int(src.get("pull_ten", 0)),
		"packs": src.get("packs", []) as Array,
		"monthly_pass": {
			"usd_cents": int(src.get("monthly_pass", {}).get("usd_cents", 0)),
			"days": int(src.get("monthly_pass", {}).get("days", 30)),
			"upfront_gems": int(src.get("monthly_pass", {}).get("upfront_gems", 300)),
			"daily_gems": int(src.get("monthly_pass", {}).get("daily_gems", 120)),
			"bank_missed_days": bool(src.get("monthly_pass", {}).get("bank_missed_days", false)),
		},
		"ad_free_pass": {
			"usd_cents": int(src.get("ad_free_pass", {}).get("usd_cents", 0)),
			"one_time": bool(src.get("ad_free_pass", {}).get("one_time", true)),
		},
		"streak_repair": {
			"gem_cost": int(src.get("streak_repair", {}).get("gem_cost", 60)),
			"max_held": int(src.get("streak_repair", {}).get("max_held", 2)),
			"ad_repairs_per_month": int(src.get("streak_repair", {}).get("ad_repairs_per_month", 1)),
		},
		"ads": {
			"max_per_day": int(src.get("ads", {}).get("max_per_day", 4)),
			"gems_per_ad": src.get("ads", {}).get("gems_per_ad"),
		},
	}


# --- helpers ----------------------------------------------------------------

static func _parsed(res: Dictionary, kind: String) -> Dictionary:
	if not bool(res.get("ok", false)):
		return {"ok": false, "data": null, "error": str(res.get("error", "request failed"))}
	var data: Variant = res.get("data")
	match kind:
		"home":
			data = parse_home(data)
		"banners":
			data = parse_banners(data)
		"pull":
			data = parse_pull(data)
		"collection":
			data = parse_collection(data)
		"set_sizes":
			data = parse_set_sizes(data)
		"daily":
			data = parse_daily(data)
		"gems":
			data = parse_gems(data)
		"shop":
			data = parse_shop(data)
	return {"ok": true, "data": data, "error": ""}


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _float_map(v: Variant, keys: Array[String]) -> Dictionary:
	var src := _dict(v)
	var out := {}
	for key in keys:
		out[key] = float(src.get(key, 0.0))
	return out


## Server ramp table -> {tier: {base, step, cap}}. A tier the server did not
## send stays absent, so the UI can say "unavailable" instead of inventing odds.
static func _ramp_map(v: Variant) -> Dictionary:
	var src := _dict(v)
	var out := {}
	for tier in RAMP_TIERS:
		if not (src.get(tier) is Dictionary):
			continue
		var r: Dictionary = src[tier]
		out[tier] = {
			"base": float(r.get("base", 0.0)),
			"step": float(r.get("step", 0.0)),
			"cap": float(r.get("cap", 0.0)),
		}
	return out
