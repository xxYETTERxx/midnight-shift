class_name TestGatedInteractable
extends Interactable

# When set, this interactable is only eligible if the player's active
# hotbar slot holds an item with this id. Leave empty for "always".
@export var required_item_id: StringName = &""


func can_interact(player: Node) -> bool:
	if required_item_id == &"":
		return true
	if player == null:
		return false
	var inv: Inventory = player.get("inventory")
	if inv == null:
		return false
	var stack := inv.get_active_stack()
	return stack != null and stack.item != null and stack.item.id == required_item_id
