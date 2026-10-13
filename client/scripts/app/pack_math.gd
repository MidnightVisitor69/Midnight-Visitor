class_name PackMath
extends RefCounted
## Pure pack/odds formatting for the Home tab. No nodes, no network: the screen
## and the tests read the same numbers, so a label can never drift from the
## pity rules the server publishes (AGENTS.md: odds visible before purchase).

const RARITY_LABELS := {
	"common": "Common",
	"rare": "Rare",
	"epic": "Epic",
	"legendary": "Legendary",
}
const HOLO_LABELS := {
	"none": "None",
	"silver": "Silver",
	"rainbow": "Rainbow",
	"gold": "Gold",
	"prism": "Prism",
	"galaxy": "Galaxy",
}
## Tiers whose per-pull odds climb (T-013). Names only: the numbers are the server's.
const RAMP_TIERS: Array[String] = ["epic", "legendary"]
const TIER_LABELS := {
	"epic": "Epic",
	"legendary": "Legendary",
}


## Server sends fractions (0.015); players need "1.5%", one decimal.
static func format_percent(fraction: float) -> String:
	return "%.1f%%" % (fraction * 100.0)


## Soft-pity odds for one tier: min(base + step * since, cap). base/step/cap come
## from the server's banner JSON; only the arithmetic is ours (T-013).
static func ramp_odds(ramp: Dictionary, since: int) -> float:
	var base := float(ramp.get("base", 0.0))
	var step := float(ramp.get("step", 0.0))
	var cap := float(ramp.get("cap", 0.0))
	return minf(base + step * float(maxi(since, 0)), cap)


## The pull screen's pity line, in plain language. Every number comes from the
## server: the ramp table (base/step/cap) and the player's counters. A banner
## with no ramp data says so rather than guessing.
static func pity_text(home_pity: Dictionary, banner_pity: Dictionary) -> String:
	var raw: Variant = banner_pity.get("ramp")
	var ramp: Dictionary = raw if raw is Dictionary else {}
	var parts: Array[String] = []
	for tier in RAMP_TIERS:
		if not (ramp.get(tier) is Dictionary):
			continue
		var r: Dictionary = ramp[tier]
		var since := int(home_pity.get("since_" + tier, 0))
		parts.append("%s odds rise every pull since your last %s (%s now, up to %s)" % [
			TIER_LABELS[tier], tier,
			format_percent(ramp_odds(r, since)),
			format_percent(float(r.get("cap", 0.0))),
		])
	if parts.is_empty():
		return "Pity odds unavailable."
	return " · ".join(parts)


## "Common 70.0% · Rare 20.0% · ..." for any odds map; keys keep server order.
static func odds_text(odds: Dictionary, keys: Array[String], labels: Dictionary) -> String:
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s %s" % [str(labels.get(key, key)), format_percent(float(odds.get(key, 0.0)))])
	return " · ".join(parts)


static func rarity_odds_text(odds: Dictionary) -> String:
	return odds_text(odds, Api.ODDS_KEYS, RARITY_LABELS)


static func holo_odds_text(odds: Dictionary) -> String:
	return odds_text(odds, Api.HOLO_KEYS, HOLO_LABELS)


## Plain fallback list for a pull result when no reveal screen is listening yet
## (T-007 takes over). A missing card_id still shows a placeholder, never blank.
static func cards_summary(cards: Array) -> String:
	var parts: Array[String] = []
	for item in cards:
		if not (item is Dictionary):
			continue
		var card: Dictionary = item
		var name := str(card.get("card_id", "?"))
		var variant := str(card.get("variant", "none"))
		parts.append(name + (" [%s]" % variant if variant != "none" else ""))
	return ", ".join(parts)
