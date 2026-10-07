class_name HoloVariants
extends RefCounted
## Single source of truth for the foil variants. The order and names MUST match
## the DB enum public.holo_variant; the test suite compares the two so a
## migration can never drift away from the client silently.
##
## A variant is pure presentation: one shader plus one GradientTexture1D ramp.
## The server rolls the variant and stores it on user_cards.variant, but the
## client still re-checks the rarity rule so a malicious payload can't force a
## foil onto a common (AGENTS.md "Golden rule: server decides everything").

const VARIANTS: Array[String] = ["none", "silver", "rainbow", "gold", "prism", "galaxy"]

## Holo exists on rare and up only.
const HOLO_RARITIES: Array[String] = ["rare", "epic", "legendary"]

const SHADERS := {
	"silver": "res://shaders/holo/silver.gdshader",
	"rainbow": "res://shaders/holo/rainbow.gdshader",
	"gold": "res://shaders/holo/gold.gdshader",
	"prism": "res://shaders/holo/prism.gdshader",
	"galaxy": "res://shaders/holo/galaxy.gdshader",
}

const RAMPS := {
	"silver": "res://shaders/holo/ramps/silver.tres",
	"rainbow": "res://shaders/holo/ramps/rainbow.tres",
	"gold": "res://shaders/holo/ramps/gold.tres",
	"prism": "res://shaders/holo/ramps/prism.tres",
	"galaxy": "res://shaders/holo/ramps/galaxy.tres",
}


## Shader for a variant, or null for "none"/unknown. load() (not preload) so a
## missing file is a caught null rather than a parse error.
static func shader_for(variant: String) -> Shader:
	if not SHADERS.has(variant):
		return null
	return load(SHADERS[variant]) as Shader


## Color ramp for a variant, or null for "none"/unknown.
static func ramp_for(variant: String) -> Texture2D:
	if not RAMPS.has(variant):
		return null
	return load(RAMPS[variant]) as Texture2D


## Whether this rarity may show this foil. Commons never do, and "none" is a
## real enum value, not an absence.
static func applies_to(rarity: String, variant: String) -> bool:
	if not SHADERS.has(variant):
		return false
	return HOLO_RARITIES.has(rarity)
