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


## Server sends fractions (0.015); players need "1.5%", one decimal.
static func format_percent(fraction: float) -> String:
	return "%.1f%%" % (fraction * 100.0)


## Pulls left until a pity guarantee fires. target_at is the pull number that
## triggers it, since is the pulls already done without a hit: 10/0 -> 10,
## 10/9 -> 1. Never negative: a fired pity restarts at the next threshold.
static func pulls_until(target_at: int, since: int) -> int:
	return maxi(target_at - since, 0)


## "in N" half of a pity line; the caller adds the noun.
static func guarantee_phrase(target_at: int, since: int) -> String:
	return "in %d" % pulls_until(target_at, since)


## Both pity guarantees from home.pity and the banner's rules.
static func pity_text(pity: Dictionary, rules: Dictionary) -> String:
	return "Epic+ guaranteed %s pulls · Legendary guaranteed %s pulls" % [
		guarantee_phrase(int(rules.get("epic_every", 0)), int(pity.get("since_epic", 0))),
		guarantee_phrase(int(rules.get("legendary_at", 0)), int(pity.get("since_legendary", 0))),
	]


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
