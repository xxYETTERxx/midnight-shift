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

# Tile centers occupied by `item` if its anchor tile is `tile_center`.
# For multi-tile footprints, the anchor is the top-left tile.
func _footprint_tiles_at(item: PlaceableItemDef, tile_center: Vector2) -> Array:
	var tiles: Array = []
	for x in range(item.footprint_tiles.x):
		for y in range(item.footprint_tiles.y):
			tiles.append(tile_center + Vector2(x * TILE_SIZE, y * TILE_SIZE))
	return tiles
	
func _is_placement_valid(item: PlaceableItemDef, tile_center: Vector2) -> bool:
	var new_tiles: Array = _footprint_tiles_at(item, tile_center)

	# Surface check — every tile must satisfy the item's surface rules.
	for t in new_tiles:
		if not _tile_is_valid_surface(t, item.placement_surface):
			return false

	# Overlap check — no existing placeable may share any tile.
	var container := _get_placeables_container()
	if container == null:
		return true
	for child in container.get_children():
		if not (child is Placeable):
			continue
		var other: Placeable = child
		if other.source_item == null:
			continue
		var other_tiles: Array = _footprint_tiles_at(other.source_item, other.global_position)
		for t in new_tiles:
			if t in other_tiles:
				return false
	return true


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

func _tile_is_valid_surface(world_pos: Vector2, surface: int) -> bool:
	var room := RoomManager.current_room
	if room == null:
		return false
	var coords: Vector2i = _world_to_tile_coords(world_pos)
	var floor_map := room.get_node_or_null("Floor") as TileMap
	var walls_base := room.get_node_or_null("WallsBase") as TileMap
	var walls_top := room.get_node_or_null("WallsTop") as TileMap
	match surface:
		PlaceableItemDef.Surface.FLOOR:
			if floor_map == null:
				return false
			if floor_map.get_cell_source_id(0, coords) == -1:
				return false
			if walls_base != null and walls_base.get_cell_source_id(0, coords) != -1:
				return false
			if walls_top != null and walls_top.get_cell_source_id(0, coords) != -1:
				return false
			return true
		PlaceableItemDef.Surface.CEILING:
			# Ceiling rules deferred until you have a ceiling item to test against.
			return true
	return false

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

	if not _placement_allowed_in_current_room():
		return false

	var item: PlaceableItemDef = stack.item
	if item.placeable_scene == null:
		push_warning("PlaceableItemDef '%s' has no placeable_scene" % item.id)
		return false

	var container := _get_placeables_container()
	if container == null:
		return false

	var target_pos := PlacementSystem.tile_in_front_of(player)
	if _is_tile_occupied(target_pos):
		return false

	var instance: Placeable = item.placeable_scene.instantiate()
	container.add_child(instance)
	instance.global_position = target_pos
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
	if not _placement_allowed_in_current_room():
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

func try_pickup_targeted(player: Node) -> bool:
	if player.is_holding_anything():
		return false

	var winner: Node = InteractionManager.active
	if winner == null:
		return false

	var placeable: Placeable = Placeable.find_owning_placeable(winner)
	if placeable == null:
		return false

	if not placeable.can_pickup():
		push_warning(placeable.pickup_refusal_reason())
		return false

	if placeable.source_item == null:
		push_warning("Placeable has no source_item — cannot return to inventory")
		return false

	var inv: Inventory = player.get("inventory")
	if inv == null:
		return false

	var leftover: int = inv.add(placeable.source_item, 1)
	if leftover > 0:
		push_warning("No inventory space to pick up %s" % placeable.source_item.id)
		return false

	placeable.queue_free()
	return true

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
	
func _world_to_tile_coords(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / TILE_SIZE)),
		int(floor(world_pos.y / TILE_SIZE)),
	)

func _placement_allowed_in_current_room() -> bool:
	var room := RoomManager.current_room
	if room == null:
		return false
	return room.is_in_group("placement_allowed")
	
func _is_tile_occupied(tile_center: Vector2) -> bool:
	var container := _get_placeables_container()
	if container == null:
		return false
	for child in container.get_children():
		if child is Placeable:
			# Tile centers always land on .5 offsets thanks to snap_to_tile,
			# so an exact-position match is reliable for single-tile items.
			if child.global_position.is_equal_approx(tile_center):
				return true
	return false
