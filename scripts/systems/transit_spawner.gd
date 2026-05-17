extends Node

# Drives transit NPC spawning. Each in-game minute (during waking hours)
# rolls a chance to spawn one transit pedestrian on a random authored
# route through the current room. Transit NPCs are ephemeral — they
# despawn at their route's end, and any still-walking ones get culled
# automatically when the room unloads.

const TRANSIT_NPC_SCENE: PackedScene = preload("res://scenes/components/transit_npc.tscn")

@export var spawn_chance_per_minute: float = 0.10
@export var max_concurrent: int = 6

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _live_npcs: Array = []


func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()
	TimeSystem.minute_tick.connect(_on_minute_tick)


func _on_minute_tick(_total: int) -> void:
	_prune_dead()
	if _live_npcs.size() >= max_concurrent:
		return
	if _rng.randf() > spawn_chance_per_minute:
		return
	_try_spawn()


func _prune_dead() -> void:
	var alive: Array = []
	for n in _live_npcs:
		if is_instance_valid(n):
			alive.append(n)
	_live_npcs = alive


func _try_spawn() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var route_ids: Array = TransitRoutes.pick_random_route(_rng)
	if route_ids.size() < 2:
		return

	# Optionally reverse — doubles route variety without authoring overhead.
	if _rng.randf() < 0.5:
		route_ids = route_ids.duplicate()
		route_ids.reverse()

	var positions: Array[Vector2] = []
	for wp_id in route_ids:
		var pos = _resolve_waypoint(room, wp_id)
		if pos == null:
			# Route references a waypoint not in this room — skip silently.
			return
		positions.append(pos)

	var npc: TransitNPC = TRANSIT_NPC_SCENE.instantiate()
	room.add_child(npc)
	npc.walk_route(positions)
	_live_npcs.append(npc)


# Same resolver pattern as MeetingSpawner. Fourth copy at this point;
# we should hoist this to a shared utility next time we touch any of these.
func _resolve_waypoint(room: Node, waypoint_id: StringName):
	var container: Node = room.get_node_or_null("Waypoints")
	if container != null:
		for child in container.get_children():
			if child is Waypoint and child.waypoint_id == waypoint_id:
				return child.global_position
	return _find_in_subtree(room, waypoint_id)


func _find_in_subtree(node: Node, waypoint_id: StringName):
	if node is Waypoint and node.waypoint_id == waypoint_id:
		return node.global_position
	for child in node.get_children():
		var hit = _find_in_subtree(child, waypoint_id)
		if hit != null:
			return hit
	return null
