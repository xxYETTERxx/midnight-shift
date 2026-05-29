class_name Recipe
extends Resource

# A single transformation rule: inputs (consumed) + required tools (held, not
# consumed) → output. Authored as a .tres file in res://data/recipes/.
# Stations filter which recipes appear at which interactable. Empty tags
# means "appears at any station" — useful while there's only one station.

@export var id: StringName = &""

# Player-facing name. Falls back to the output item's display_name in UI
# if left blank.
@export var display_name: String = ""

# Inputs are consumed on craft. All must be present in the count specified.
@export var inputs: Array[RecipeInput] = []

@export var output_item: ItemDef
@export var output_count: int = 1

# Recipe appears at a station only if the station's tag is in this list,
# OR this list is empty (recipe is station-agnostic). Cooking will populate
# this with [&"stove"] etc; the dime bag and ziplock recipes use [&"counter"].
@export var station_tags: Array[StringName] = []

# Tools that must be in the player's inventory but are NOT consumed.
# Multiple = all required.
@export var required_tools: Array[ItemDef] = []

# Optional progression gate. If set, recipe is hidden until the named global
# flag is true. Use sparingly — most recipes should be visible-but-uncraftable
# so the player can see what to work toward.
@export var unlock_flag: String = ""

# Base cost per CRAFT (not per output unit) — added on top of tool per-unit
# costs. Use this for one-time setup overhead, or for recipes with no
# per-unit-shaped tool (a brew batch that takes 8 hours regardless of yield).
@export var base_time_seconds: float = 0.0
@export var base_stamina: float = 0.0

# Maximum batch size in one craft action. The panel quantity field clamps
# to this. Defaults to 99 so most recipes have no practical cap.
@export var max_batch: int = 99
