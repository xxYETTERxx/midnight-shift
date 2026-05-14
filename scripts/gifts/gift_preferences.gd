class_name GiftPreferences
extends Resource

# Per-NPC gift preferences. Categories not in tier_overrides default to NEUTRAL.
# Reaction line overrides are optional — empty means use the global default.

@export var npc_id: StringName = ""

# Maps ItemDef.Category (int) -> GiftSystem.Tier (int).
# Inspector authoring: typed Dictionary with sub-resource keys would be nicer
# but Godot's inspector doesn't support that cleanly for enum keys, so the
# pragmatic shape is two parallel arrays the GiftSystem zips at load time.
@export var like_categories: Array[ItemDef.Category] = []
@export var love_categories: Array[ItemDef.Category] = []
@export var dislike_categories: Array[ItemDef.Category] = []
@export var hate_categories: Array[ItemDef.Category] = []

# Optional per-NPC reaction line overrides. Empty = use global default.
@export_multiline var hate_line: String = ""
@export_multiline var dislike_line: String = ""
@export_multiline var neutral_line: String = ""
@export_multiline var like_line: String = ""
@export_multiline var love_line: String = ""
@export_multiline var perfect_line: String = ""
