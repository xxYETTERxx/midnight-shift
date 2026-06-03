class_name DroppedItem
extends Node2D

# An item lying in the world after being dropped from the inventory. Walk up,
# interact, it goes back into the player's pack. Wiped on day rollover (litter
# doesn't survive the night). Spawned at the player's feet by the inventory
# panel's drop gesture.

@onready var sprite: Sprite2D = $Sprite
@onready var interactable: Interactable = $Interactable

var item: ItemDef = null
var count: int = 1


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	_refresh_visual()


# Stamp this pickup with what it represents. Called right after instantiation.
func setup(item_def: ItemDef, item_count: int) -> void:
	item = item_def
	count = item_count
	if is_node_ready():
		_refresh_visual()


func _refresh_visual() -> void:
	if item != null and item.icon != null:
		sprite.texture = item.icon
	if interactable != null and item != null:
		interactable.prompt_text = "Pick up %s" % item.display_name


func _on_interacted(player_node: Node) -> void:
	if item == null:
		queue_free()
		return
	var inv: Inventory = player_node.inventory
	var leftover: int = inv.add(item, count)
	if leftover == count:
		NotificationSystem.warn("Inventory full.")
		return
	if leftover > 0:
		# Partial pickup — pack filled. Leave the remainder on the ground.
		count = leftover
		NotificationSystem.warn("Picked up some — pack's full.")
		return
	queue_free()
