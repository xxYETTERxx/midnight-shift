extends Node

# Per-room persisted placeable state.
# Keyed by room scene_file_path (e.g., "res://scenes/rooms/apartment_living.tscn").
# Value is an Array of Dictionaries — each one is a Placeable's save_state()
# output, plus a "scene_path" key telling us what scene to instantiate on restore.
#
# Example:
# {
#   "res://scenes/rooms/apartment_living.tscn": [
#     { "scene_path": "res://scenes/components/pot.tscn",
#       "item_id": "pot_basic", "x": 240, "y": 176,
#       "container_state": 1, "plant_stage": 0, "soil_uses_remaining": 3,
#       "watered_today": false, "modifiers": [] },
#     ...
#   ]
# }
var _room_states: Dictionary = {}


func _ready() -> void:
	SaveSystem.register_savable("world_state", self)
	TimeSystem.day_rolled.connect(_on_day_rolled)


# Capture the placeable state of a room into the persisted dictionary.
# Called by RoomManager before unloading a room.
func snapshot_room(room: Node) -> void:
	
	if room == null:
		return
	var room_path: String = room.scene_file_path
	if room_path == "":
		push_warning("WorldStateSystem: room has no scene_file_path, cannot snapshot")
		return

	var placeables_container := room.get_node_or_null("Placeables")
	if placeables_container == null:
		# No Placeables container = nothing to snapshot. Clear any prior state
		# for this room so a stale snapshot doesn't linger.
		_room_states[room_path] = []
		return

	var snapshots: Array = []
	for child in placeables_container.get_children():
		if not (child is Placeable):
			continue
		var state = child.save_state()
		# Tack on the scene path so restore knows what to instantiate.
		# Source the scene path from the source ItemDef rather than from
		# the live node — items are the canonical reference.
		if child.source_item != null and child.source_item.placeable_scene != null:
			state["scene_path"] = child.source_item.placeable_scene.resource_path
		else:
			push_warning("WorldStateSystem: placeable has no source_item or scene, skipping")
			continue
		snapshots.append(state)

	_room_states[room_path] = snapshots


# Restore the placeable state of a room. Called by RoomManager after
# instancing a room and positioning the player.
func restore_room(room: Node) -> void:
	print("[restore_room] called for ", room.scene_file_path, " | _room_states keys: ", _room_states.keys())
	if room == null:
		return
	var room_path: String = room.scene_file_path
	if room_path == "":
		return
	if not _room_states.has(room_path):
		# Room has never been snapshotted — fresh room, nothing to restore.
		return

	var placeables_container := room.get_node_or_null("Placeables")
	if placeables_container == null:
		# Lazy-create, mirroring PlacementSystem's behavior so rooms
		# authored without an explicit Placeables container still work.
		placeables_container = Node2D.new()
		placeables_container.name = "Placeables"
		placeables_container.y_sort_enabled = true
		room.add_child(placeables_container)

	var snapshots: Array = _room_states[room_path]
	for state in snapshots:
		var scene_path: String = state.get("scene_path", "")
		if scene_path == "":
			push_warning("WorldStateSystem: snapshot missing scene_path, skipping")
			continue
		var scene: PackedScene = load(scene_path)
		if scene == null:
			push_warning("WorldStateSystem: failed to load %s" % scene_path)
			continue
		var instance: Placeable = scene.instantiate()
		placeables_container.add_child(instance)

		# Hook up source_item from the saved item_id.
		var item_id: StringName = StringName(state.get("item_id", ""))
		if item_id != &"":
			var item = ItemRegistry.get_item(item_id)
			if item is PlaceableItemDef:
				instance.on_placed(item)
			else:
				push_warning("WorldStateSystem: item %s is not placeable" % item_id)

		instance.load_state(state)


# --- SaveSystem integration ---

func save_state() -> Dictionary:
	# The dictionary is already serializable (only contains strings, numbers,
	# bools, and nested dicts/arrays of the same). Just return a copy.
	if RoomManager.current_room != null:
		snapshot_room(RoomManager.current_room)
	return { "room_states": _room_states.duplicate(true) }


func load_state(data: Dictionary) -> void:
	var loaded: Dictionary = data.get("room_states", {})
	_room_states = loaded


# --- Debug / utility ---

func clear() -> void:
	# Wipe all persisted state. Useful for "new game" or testing.
	_room_states.clear()


func has_snapshot_for(room_path: String) -> bool:
	return _room_states.has(room_path)
	
func _on_day_rolled(_dow: int, _dom: int) -> void:
	# Advance placeables in rooms the player isn't currently in.
	# The current room's live placeables tick themselves via their
	# own day_rolled listeners.
	var current_path: String = ""
	if RoomManager.current_room != null:
		current_path = RoomManager.current_room.scene_file_path

	for room_path in _room_states:
		if room_path == current_path:
			continue
		var snapshots: Array = _room_states[room_path]
		for state in snapshots:
			_tick_snapshot_for_day(state)


func _tick_snapshot_for_day(state: Dictionary) -> void:
	# Dispatch to the appropriate static tick function based on scene_path.
	# Right now only Pot has tick logic; others (lamps, stash boxes) will
	# add their own as the system grows.
	var scene_path: String = state.get("scene_path", "")
	match scene_path:
		"res://scenes/components/pot.tscn":
			Pot.tick_snapshot_day(state)
		_:
			pass  # unknown placeable, no time-based logic
