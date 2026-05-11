class_name ItemStack
extends RefCounted

var item: ItemDef
var count: int
# Per-instance state. Empty for most items; populated for items with
# per-stack data (calling cards, future: durability, marked bills, etc).
var data: Dictionary


func _init(p_item: ItemDef = null, p_count: int = 1, p_data: Dictionary = {}) -> void:
	item = p_item
	count = p_count
	data = p_data.duplicate(true)


# How many more of this item could fit in this stack?
func space_remaining() -> int:
	if item == null:
		return 0
	return item.max_stack - count


func is_full() -> bool:
	return count >= (item.max_stack if item else 1)


# True if other holds the same item type AND identical data — both required
# for merging. Two calling cards with different remaining minutes don't merge.
func can_merge_with(other: ItemStack) -> bool:
	return other != null and item != null and other.item == item and other.data == data


func to_dict() -> Dictionary:
	var d := {"id": String(item.id), "count": count}
	if not data.is_empty():
		d["data"] = data.duplicate(true)
	return d


static func from_dict(data_dict: Dictionary) -> ItemStack:
	var id := StringName(data_dict.get("id", ""))
	var item := ItemRegistry.get_item(id)
	if item == null:
		return null
	var count: int = data_dict.get("count", 1)
	var stack_data: Dictionary = data_dict.get("data", {})
	return ItemStack.new(item, count, stack_data)
