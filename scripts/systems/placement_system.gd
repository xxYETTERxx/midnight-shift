extends Node

const PREVIEW_SCRIPT := preload("res://scripts/components/placement_preview.gd")

var _preview: PlacementPreview = null

const TILE_SIZE: int = 32

const PLAYER_FEET_OFFSET: Vector2 = Vector2(10, -10)

# Direction vectors keyed by player.last_direction.
const DIRECTION_OFFSETS: Dictionary = {
	"n": Vector2(0, -1),
	"s": Vector2(0, 1),
	"e": Vector2(1, 0),
	"w": Vector2(-1, 0),
}

func _process(_delta: float) -> void:
	_update_preview()


# Returns the Placeables container node in the current room, creating
# it if missing. Future-proofs against rooms authored without it.
func _get_placeables_container() -> Node:
	var room := RoomManager.current_room
	if room == null:
		return null
	var container := room.get_node_or_null("Placeables")
	if container == null:
		container = Node2D.new()
		container.name = "Placeables"
		# Y-sort under the room (which itself is Y-sort enabled), so
		# placeables sort against tilemaps and the player correctly.
		container.y_sort_enabled = true
		room.add_child(container)
	return container


# Snap a world position to the center of its 32×32 tile.
func snap_to_tile(world_pos: Vector2) -> Vector2:
	return Vector2(
		floor(world_pos.x / TILE_SIZE) * TILE_SIZE + TILE_SIZE / 2.0,
		floor(world_pos.y / TILE_SIZE) * TILE_SIZE + TILE_SIZE / 2.0,
	)

func tile_in_front_of(player: Node) -> Vector2:
	var dir_str: String = player.get("last_direction")
	var offset: Vector2 = DIRECTION_OFFSETS.get(dir_str, Vector2(0, 1))
	var anchor := player.get_node_or_null("FeetAnchor")
	var feet: Vector2 = anchor.global_position if anchor else player.global_position
	return snap_to_tile(feet + offset * TILE_SIZE)


# Attempts to place the player's active item at their feet.
# Returns true if a placement happened (so caller knows whether to
# consume the input or fall through to other behaviors).
func try_place_active(player: Node) -> bool:
	var inv: Inventory = player.get("inventory")
	if inv == null:
		return false
	var stack := inv.get_active_stack()
	if stack == null or stack.item == null:
		return false
	if not (stack.item is PlaceableItemDef):
		return false

	var item: PlaceableItemDef = stack.item
	if item.placeable_scene == null:
		push_warning("PlaceableItemDef '%s' has no placeable_scene" % item.id)
		return false

	var container := _get_placeables_container()
	if container == null:
		return false

	# Sub-chunk 5 will add surface/footprint validation here.

	var instance: Placeable = item.placeable_scene.instantiate()
	container.add_child(instance)
	instance.global_position = PlacementSystem.tile_in_front_of(player)
	instance.on_placed(item)

	inv.consume_active(1)
	return true

func _update_preview() -> void:
	var player := _find_player()
	if player == null:
		_hide_preview()
		return
	if not _player_holds_placeable(player):
		_hide_preview()
		return
	var preview := _ensure_preview()
	if preview == null:
		return
	preview.global_position = tile_in_front_of(player)
	preview.visible = true
	# Sub-chunk 5 will compute validity properly. For now, always valid.
	preview.set_valid(true)


func _ensure_preview() -> PlacementPreview:
	if _preview != null and is_instance_valid(_preview):
		return _preview
	var room := RoomManager.current_room
	if room == null:
		return null
	_preview = PlacementPreview.new()
	room.add_child(_preview)
	return _preview


func _hide_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.visible = false


func _player_holds_placeable(player: Node) -> bool:
	var inv: Inventory = player.get("inventory")
	if inv == null:
		return false
	var stack := inv.get_active_stack()
	return stack != null and stack.item != null and stack.item is PlaceableItemDef


func _find_player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")
