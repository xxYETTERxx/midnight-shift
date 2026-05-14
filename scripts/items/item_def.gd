class_name ItemDef
extends Resource

@export var id: StringName = ""
@export var tool_id: StringName = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export_range(1, 999) var max_stack: int = 99
@export var category: Category = Category.MATERIAL
@export_multiline var description: String = ""
@export var movement_speed: float = 0.0
@export var base_value: int = 0
@export var sellable: bool = false


# Gift-system fields.
# If non-empty, giving this item to the named NPC counts as "perfect"
# instead of being graded by category. Empty = no perfect target.
@export var perfect_gift_for: StringName = ""


# Whether this item can be given as a gift at all. Tools and keys = false.
# Defaults true — most items should be giftable.
@export var giftable: bool = true


enum Category {
	# --- Legacy / inventory-side ---
	TOOL,        # 0 — watering can, lockpicks, axes. Not giftable.
	SEED,        # 1 — planted into soil pots
	MATERIAL,    # 2 — soil, baggies, raw buds
	CONSUMABLE,  # 3 — legacy, prefer FOOD/DRINK for new items
	GIFT,        # 4 — legacy, prefer specific gift category
	KEY,         # 5 — quest items. Not giftable.
	MISC,        # 6 — fallback / catch-all
	# --- Gift-side (appended; do not reorder above this line) ---
	FOOD,           # 7
	DRINK,          # 8
	FLOWER,         # 9
	JEWELRY,        # 10
	ENTERTAINMENT,  # 11 — VHS, CDs, books
	CLOTHING,       # 12
	DECORATION,     # 13 — knick-knacks, art
	DRUG,           # 14 — in-genre, some NPCs love it
}

# Override in subclasses to provide initial per-stack data when a fresh
# stack of this item is created. Most items return empty.
func initial_stack_data() -> Dictionary:
	return {}
