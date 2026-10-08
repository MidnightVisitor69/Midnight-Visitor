class_name RevealPlan
extends RefCounted
## The pack opening's brain, with no nodes and no network (task M-002). The
## screen asks this what to show and for how long; the tests pin the same
## numbers, so a reveal can never drift from what the tests believe.
##
## Two jobs:
##   1. order the received cards for drama - the richest card last, everything
##      else in pull order;
##   2. describe each card as a "beat": how long it is held, whether it flashes,
##      what colour teases it, whether it carries a pity tag.

## Server rarity order, weakest first. Never sort by the name: "legendary" <
## "rare" alphabetically, which is how the best card ends up first.
const RARITY_ORDER: Array[String] = ["common", "rare", "epic", "legendary"]

## Tease colours are the one piece of new palette this task needs. They are
## duplicated from client/theme/tokens.tres the moment that file lands (AGENTS.md
## next task 3); until then a card's rarity colour lives with the card logic so
## the tear burst and the glow ramp can never disagree about it.
const TEASE_COLORS := {
	"common": Color(0.62, 0.65, 0.72),
	"rare": Color(0.30, 0.62, 1.00),
	"epic": Color(0.68, 0.36, 1.00),
	"legendary": Color(1.00, 0.80, 0.28),
}

## What the screen must do next. Kept here (not in the Control) so "skip always
## reaches the summary" is a fact about strings, testable with no rendering.
const STEP_CLOSED := "closed"
const STEP_TEARING := "tearing"
const STEP_REVEALING := "revealing"
const STEP_SUMMARY := "summary"


## Position of a rarity in RARITY_ORDER; unknown rarities count as common so a
## malformed payload can never float to the end of a pack.
static func rank(rarity: String) -> int:
	return maxi(RARITY_ORDER.find(rarity), 0)


## The colour this rarity teases with.
static func tease_color(rarity: String) -> Color:
	return TEASE_COLORS.get(rarity, TEASE_COLORS["common"])


## How long the reveal holds this rarity (seconds). The numbers live in Motion
## so the dev tunes every timing in one place (ANIMATOR.md).
static func hold_seconds(rarity: String) -> float:
	return Motion.hold_seconds(rarity)


## The rarest rarity in the pack, or "common" for an empty one. Drives the
## light burst when the foil is ripped: the player learns how good this pack is
## before the first card turns over.
static func best_rarity(cards: Array) -> String:
	var best := "common"
	for item in cards:
		if not (item is Dictionary):
			continue
		var r := str((item as Dictionary).get("rarity", "common"))
		if rank(r) > rank(best):
			best = r
	return best


static func best_tease_color(cards: Array) -> Color:
	return tease_color(best_rarity(cards))


## Reveal order: pull order, except the best card is held back for last.
## Stable, so equal rarities keep the order the server dealt them - the player
## still reads the pack as "the cards I got", not as a reshuffle.
static func ordered(cards: Array) -> Array:
	var out: Array = []
	for item in cards:
		if not (item is Dictionary):
			continue
		var card: Dictionary = item
		var r := rank(str(card.get("rarity", "common")))
		# Walk back past strictly-richer cards only; stopping at the first card
		# no richer than this one is what keeps the sort stable.
		var at := out.size()
		while at > 0 and rank(str((out[at - 1] as Dictionary).get("rarity", "common"))) > r:
			at -= 1
		out.insert(at, card)
	return out


## One beat per card, in reveal order. Every screen reads these keys, so the
## timings cannot drift between the tear, the flip and the tests.
static func build(cards: Array) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	for card in ordered(cards):
		var c: Dictionary = card
		var rarity := str(c.get("rarity", "common"))
		var variant := str(c.get("variant", "none"))
		beats.append({
			"card": c,
			"rarity": rarity,
			"variant": variant,
			"tease_color": tease_color(rarity),
			"hold_seconds": hold_seconds(rarity),
			# Foil flash rides the same rule the CardView enforces, so a flash
			# can never promise a shine the card will not draw.
			"flash": HoloVariants.applies_to(rarity, variant),
			"pity": int(c.get("pity", 0)) != 0,
		})
	return beats


## Index of the highest-rarity card, or 0 when every card ties. Ties resolve to
## the first of them, so a pack of ten commons still "reveals the best at 0"
## rather than picking a random one.
static func best_index(cards: Array) -> int:
	var best := 0
	for i in cards.size():
		if not (cards[i] is Dictionary):
			continue
		var r := str((cards[i] as Dictionary).get("rarity", "common"))
		if r != str((cards[best] as Dictionary).get("rarity", "common")) \
				and rank(r) > rank(str((cards[best] as Dictionary).get("rarity", "common"))):
			best = i
	return best


# --- NEW badges ----------------------------------------------------------------

## A collectible is the card AND its foil (AGENTS.md: same card, different
## variant = different collectible), so the key carries both.
static func owned_key(card_id: String, variant: String) -> String:
	return "%s|%s" % [card_id, variant]


## Whether `card` was already in the player's collection before the pull.
static func was_owned(card: Dictionary, owned_before: Array) -> bool:
	var key := owned_key(str(card.get("card_id", "")), str(card.get("variant", "none")))
	for row in owned_before:
		var d := row as Dictionary
		if d.is_empty():
			continue
		if owned_key(str(d.get("card_id", "")), str(d.get("variant", "none"))) == key:
			return true
	return false


## NEW flag per card, parallel to `cards`. A second copy of the same card inside
## one pack is a duplicate, not a new collectible, so only the first is badged -
## and the copy also becomes "owned" for the rest of this pack.
static func new_flags(cards: Array, owned_before: Array) -> Array[bool]:
	var seen := {}
	for row in owned_before:
		var d := row as Dictionary
		if not d.is_empty():
			seen[owned_key(str(d.get("card_id", "")), str(d.get("variant", "none")))] = true
	var flags: Array[bool] = []
	for item in cards:
		if not (item is Dictionary):
			flags.append(false)
			continue
		var card: Dictionary = item
		var key := owned_key(str(card.get("card_id", "")), str(card.get("variant", "none")))
		flags.append(not seen.has(key))
		seen[key] = true
	return flags


# --- the reveal state machine ---------------------------------------------------

## Every step the player can skip FROM. The summary cannot be skipped out of:
## it is the end, and the only way on is Done.
const SKIPPABLE_STEPS: Array[String] = [STEP_CLOSED, STEP_TEARING, STEP_REVEALING]


## Skip always lands on the summary, from every skippable step (task M-002).
## Written as a rule rather than as `return STEP_SUMMARY` in the Control so the
## state machine can be tested with no rendering and no scene tree.
static func skip_to(step: String) -> String:
	return STEP_SUMMARY


## The step after a tap: pack -> tear -> first reveal.
static func tap_advance(step: String) -> String:
	match step:
		STEP_CLOSED, STEP_TEARING:
			return STEP_REVEALING
		STEP_REVEALING:
			return STEP_REVEALING
		_:
			return STEP_SUMMARY


## Resuming after the app died mid-reveal: `torn` says the rip finished, and
## `revealed_index` is the last card that finished flipping (-1 for none).
## The reveal picks up at revealed_index + 1, never replaying a card the player
## already saw - but the same cards, because they came from the same result.
static func resume_step(torn: bool, revealed_index: int) -> String:
	return STEP_REVEALING if torn or revealed_index >= 0 else STEP_CLOSED


## The card a resumed reveal should show first.
static func resume_index(revealed_index: int) -> int:
	return maxi(revealed_index + 1, 0)