extends Node

# Emitted just after a room is loaded and the player is positioned.
signal room_changed(room_name: String)

@export var initial_room: String = "res://scenes/rooms/apartment_v1.tscn"
@export var initial_spawn: String = "default"

var current_room: Node = null
var _world: Node = null
var _player: Node2D = null


func register_world(world: Node, player: Node2D) -> void:
	register_world_only(world, player)
	change_room(initial_room, initial_spawn)

func register_world_only(world: Node, player: Node2D) -> void:
	_world = world
	_player = player

func change_room(room_path: String, spawn_name: String) -> void:
	if _world == null:
		push_error("RoomManager: world not registered")
		return

	var slot: Node = _world.get_node("CurrentRoom")

	# Free old room
	if current_room != null:
		WorldStateSystem.snapshot_room(current_room)
		slot.remove_child(current_room)
		current_room.queue_free()
		current_room = null

	# Instance and add new room
	var room_scene: PackedScene = load(room_path)
	if room_scene == null:
		push_error("RoomManager: failed to load %s" % room_path)
		return

	current_room = room_scene.instantiate()
	slot.add_child(current_room)

	# Position player at the requested spawn point
	var spawn_node := current_room.get_node_or_null("SpawnPoints/" + spawn_name)
	if spawn_node == null:
		push_warning("RoomManager: spawn '%s' not found in room, using (0,0)" % spawn_name)
		_player.global_position = Vector2.ZERO
	else:
		_player.global_position = spawn_node.global_position

	WorldStateSystem.restore_room(current_room)
	
	room_changed.emit(current_room.name)
