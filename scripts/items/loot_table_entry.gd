class_name LootTableEntry
extends Resource

@export var item: ItemDef
@export var count_min: int = 1
@export var count_max: int = 1

# Relative likelihood vs. other entries. 1.0 = normal, 0.1 = rare, 5.0 = common.
@export var weight: float = 1.0
