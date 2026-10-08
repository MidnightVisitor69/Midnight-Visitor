class_name TokenSet
extends Resource
## The typed data behind tokens.tres (D-001). Every color, font size, spacing
## step, radius and duration the game uses lives here as data; nothing else in
## the project may hardcode them (AGENTS.md: hardcoded values are bugs).
##
## Keys are StringNames so call sites read like design language:
##   Tokens.color(&"accent"), Tokens.font_size(&"title"), Tokens.space(&"s16").
## The test suite (test_tokens.gd) pins contrast, the type-scale order and the
## 8-px grid, so a bad value fails CI instead of shipping.

## Look: "Neon After-Hours" - deep navy seen through rain-streaked glass.
## Neon is a precious resource: magenta accent, cyan secondary, amber for
## rewards only. Hierarchy comes from size and spacing, never from glow.
@export var colors: Dictionary = {
	&"bg": Color(0.027, 0.039, 0.071),            # #070A12 deep navy base
	&"surface_1": Color(0.055, 0.078, 0.141),     # #0E1424
	&"surface_2": Color(0.082, 0.110, 0.188),     # #151C30
	&"surface_3": Color(0.114, 0.153, 0.251),     # #1D2740
	&"outline": Color(0.165, 0.212, 0.329),       # #2A3654
	&"text_primary": Color(0.929, 0.945, 0.980),  # #EDF1FA on navy >= 12:1
	&"text_secondary": Color(0.655, 0.698, 0.800),  # #A7B2CC on navy >= 4.5:1
	&"text_disabled": Color(0.420, 0.463, 0.580), # #6B7694 (disabled only)
	&"accent": Color(1.0, 0.239, 0.545),          # #FF3D8B signage magenta
	&"accent_secondary": Color(0.216, 0.902, 1.0),  # #37E6FF cool cyan
	&"reward": Color(1.0, 0.761, 0.294),          # #FFC24B gems only
	&"success": Color(0.290, 0.871, 0.502),       # #4ADE80
	&"danger": Color(0.973, 0.443, 0.443),        # #F87171
	&"rarity_common": Color(0.604, 0.655, 0.769),  # #9AA7C4
	&"rarity_rare": Color(0.216, 0.902, 1.0),     # cyan
	&"rarity_epic": Color(1.0, 0.239, 0.545),     # magenta
	&"rarity_legendary": Color(1.0, 0.761, 0.294),  # amber
}

## Type scale in px at the 1080x1920 design resolution, strictly increasing
## (pinned by test). Unbounded carries display/title; Manrope everything else.
@export var font_sizes: Dictionary = {
	&"caption": 12,
	&"label": 14,
	&"body": 16,
	&"title": 22,
	&"display_m": 28,
	&"display_l": 38,
	&"display_xl": 52,
}

## 8-px grid steps (4 is the half-step for icon/badge insets).
@export var spacing: Dictionary = {
	&"s4": 4, &"s8": 8, &"s12": 12, &"s16": 16,
	&"s24": 24, &"s32": 32, &"s40": 40, &"s48": 48,
}

@export var radii: Dictionary = {
	&"small": 8,
	&"large": 16,
	&"pill": 999,
}

## Motion durations in ms (AGENTS.md: motion has a job; nothing idles).
@export var durations: Dictionary = {
	&"tap": 80,
	&"quick": 150,
	&"standard": 250,
	&"emphasized": 400,
}

## Tween easing names as Godot spellings: "out", "in_out", "out_back".
@export var easings: Dictionary = {
	&"standard": "out",
	&"entrance": "out_back",
	&"exit": "in",
}

## OFL fonts already committed under client/theme/fonts/.
@export var font_display_path: String = "res://theme/fonts/Unbounded-Variable.ttf"
@export var font_ui_path: String = "res://theme/fonts/Manrope-Variable.ttf"
