class_name ItemStack
extends RefCounted

var item: ItemDef
var count: int


func _init(p_item: ItemDef = null, p_count: int = 1) -> void:
	item = p_item
	count = p_count


# How many more of this item could fit in this stack?
func space_remaining() -> int:
	if item == null:
		return 0
	return item.max_stack - count


func is_full() -> bool:
	return count >= (item.max_stack if item else 1)


# True if other holds the same item type and could potentially merge.
func can_merge_with(other: ItemStack) -> bool:
	return other != null and item != null and other.item == item


func to_dict() -> Dictionary:
	return {"id": String(item.id), "count": count}


static func from_dict(data: Dictionary) -> ItemStack:
	var id := StringName(data.get("id", ""))
	var item := ItemRegistry.get_item(id)
	if item == null:
		return null
	var count: int = data.get("count", 1)
	return ItemStack.new(item, count)
