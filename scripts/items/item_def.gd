class_name ItemDef
extends Resource

# Stable identifier used in save files. Must be unique across all ItemDefs.
# This is the canonical name — file paths can change, but id cannot.
@export var id: StringName = ""

@export var display_name: String = ""

@export var icon: Texture2D

# Maximum count per stack. 1 = unstackable (tools, weapons).
@export_range(1, 999) var max_stack: int = 99

# What kind of item this is, for UI grouping and behavior dispatch.
@export var category: Category = Category.MATERIAL

# Optional flavor text shown on hover/long-press.
@export_multiline var description: String = ""

# Canonical worth in dollars. Vendors apply their own multipliers.
# 0 = effectively unsellable/unbuyable regardless of `sellable`.
@export var base_value: int = 0

# Whether wholesale buyers (the Fence, etc.) will accept this item.
# Tools, keys, and quest items typically should NOT be sellable.
@export var sellable: bool = false


enum Category {
	TOOL,        # watering can, lockpicks, axes — never consumed on use
	SEED,        # planted into soiled pots
	MATERIAL,    # soil, baggies, raw buds
	CONSUMABLE,  # food, drugs (when those exist)
	GIFT,        # explicitly giftable items (jewelry, etc.)
	KEY,         # quest items, keys to specific locations
	MISC,
}
