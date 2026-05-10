class_name LootTable
extends Resource

# A weighted loot table. On `roll()`, returns a list of {item, count} drops.
# Configurable per-tier in the inspector via .tres files.

@export var entries: Array[LootTableEntry] = []

# How many independent rolls happen per `roll()` call. A tier-0 car might
# do 1-2 rolls (small loot pile); a tier-2 car might do 4-6.
@export var rolls_min: int = 1
@export var rolls_max: int = 2

# Chance per-roll that the result is "nothing" (no item dropped). Lets
# tables feel inconsistent without authoring "empty" entries explicitly.
@export_range(0.0, 1.0, 0.01) var empty_chance: float = 0.0


func roll(rng: RandomNumberGenerator) -> Array:
	var num_rolls: int = rng.randi_range(rolls_min, rolls_max)
	var drops: Array = []
	for i in range(num_rolls):
		if rng.randf() < empty_chance:
			continue
		var entry := _pick_weighted_entry(rng)
		if entry == null or entry.item == null:
			continue
		var count: int = rng.randi_range(entry.count_min, entry.count_max)
		if count > 0:
			drops.append({"item": entry.item, "count": count})
	return drops


func _pick_weighted_entry(rng: RandomNumberGenerator) -> LootTableEntry:
	if entries.is_empty():
		return null
	var total_weight: float = 0.0
	for e in entries:
		total_weight += e.weight
	if total_weight <= 0.0:
		return null
	var pick: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for e in entries:
		cumulative += e.weight
		if pick <= cumulative:
			return e
	return entries.back()
